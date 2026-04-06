defmodule PocketidScimSync.Worker do
  use GenServer
  require Logger

  @sync_interval :timer.minutes(30)

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  def init(_opts) do
    config = %{
      pocket_id_url: Application.fetch_env!(:pocketid_scim_sync, :pocket_id_url),
      pocket_id_admin_key: Application.fetch_env!(:pocketid_scim_sync, :pocket_id_admin_key),
      aws_scim_endpoint: Application.fetch_env!(:pocketid_scim_sync, :aws_scim_endpoint),
      aws_scim_token: Application.fetch_env!(:pocketid_scim_sync, :aws_scim_token)
    }

    schedule_sync(1000)
    {:ok, config}
  end

  def handle_info(:sync, config) do
    perform_sync(config)
    schedule_sync(@sync_interval)
    {:noreply, config}
  end

  defp perform_sync(config) do
    Logger.info("Starting SCIM reconciliation loop...")

    with {:ok, pocket_users} <- fetch_pocket_id_users(config),
         {:ok, aws_users} <- fetch_aws_users(config) do
      # 1. Create a Set of PocketID emails for O(1) lookup
      pocket_emails = MapSet.new(pocket_users, fn u -> u["email"] end)

      # 2. Upsert (Create/Update) all users currently in PocketID
      Enum.each(pocket_users, &upsert_to_aws(&1, config))

      # 3. Find and Delete users in AWS that are NOT in PocketID
      aws_users
      |> Enum.filter(fn aws_user -> !MapSet.member?(pocket_emails, aws_user["userName"]) end)
      |> Enum.each(&delete_from_aws(&1, config))

      Logger.info("Reconciliation complete.")
    end
  end

  # --- API Fetchers ---

  defp fetch_pocket_id_users(config) do
    url = "#{config.pocket_id_url}/api/users"
    headers = ["X-API-KEY": config.pocket_id_admin_key]

    case Req.get(url, headers: headers) do
      {:ok, %{status: 200, body: %{"data" => users}}} ->
        {:ok, users}

      {:ok, %{status: status, body: body}} ->
        Logger.error("PocketID error #{status}: #{inspect(body)}")
        :error

      {:error, error} ->
        Logger.error("Failed to fetch PocketID users: #{inspect(error)}")
        :error
    end
  end

  defp fetch_aws_users(config) do
    url = config.aws_scim_endpoint <> "/Users"

    # Note: AWS SCIM usually paginates. For small homelabs, the default (50) is usually enough.
    case Req.get(url, auth: {:bearer, config.aws_scim_token}) do
      {:ok, %{status: 200, body: %{"Resources" => users}}} ->
        {:ok, users}

      # Handle case with 0 users
      {:ok, %{status: 200, body: _}} ->
        {:ok, []}

      error ->
        Logger.error("Failed to fetch AWS users: #{inspect(error)}")
        :error
    end
  end

  # --- AWS Actions ---

  defp upsert_to_aws(user, config) do
    email = user["email"]
    display_name = "#{user["firstName"]} #{user["lastName"]}"
    scim_url = config.aws_scim_endpoint <> "/Users"

    body = %{
      schemas: ["urn:ietf:params:scim:schemas:core:2.0:User"],
      userName: email,
      displayName: display_name,
      name: %{
        formatted: display_name,
        givenName: user["firstName"],
        familyName: user["lastName"]
      },
      emails: [%{value: email, primary: true, type: "work"}],
      active: true
    }

    case Req.post(scim_url, json: body, auth: {:bearer, config.aws_scim_token}) do
      {:ok, %{status: 201}} -> Logger.info("Created user: #{email}")
      {:ok, %{status: 409}} -> Logger.debug("User exists: #{email}")
      error -> Logger.error("Failed upsert for #{email}: #{inspect(error)}")
    end
  end

  defp delete_from_aws(aws_user, config) do
    # SCIM Delete requires the AWS Internal ID, not the username
    id = aws_user["id"]
    email = aws_user["userName"]
    url = config.aws_scim_endpoint <> "/Users/#{id}"

    Logger.warning("Deleting stale user from AWS: #{email}")

    case Req.delete(url, auth: {:bearer, config.aws_scim_token}) do
      {:ok, %{status: 204}} -> Logger.info("Successfully deleted #{email}")
      error -> Logger.error("Failed to delete #{email}: #{inspect(error)}")
    end
  end

  defp schedule_sync(interval), do: Process.send_after(self(), :sync, interval)
end
