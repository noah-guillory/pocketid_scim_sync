defmodule PocketidScimSync.Worker do
  use GenServer
  require Logger

  @sync_interval :timer.minutes(30)

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  def init(state) do
    schedule_sync(1000)
    {:ok, state}
  end

  def handle_info(:sync, state) do
    perform_sync()
    schedule_sync(@sync_interval)
    {:noreply, state}
  end

  defp perform_sync do
    Logger.info("Starting SCIM reconciliation loop...")

    with {:ok, pocket_users} <- fetch_pocket_id_users(),
         {:ok, aws_users} <- fetch_aws_users() do
      # 1. Create a Set of PocketID emails for O(1) lookup
      pocket_emails = MapSet.new(pocket_users, fn u -> u["email"] end)

      # 2. Upsert (Create/Update) all users currently in PocketID
      Enum.each(pocket_users, &upsert_to_aws/1)

      # 3. Find and Delete users in AWS that are NOT in PocketID
      aws_users
      |> Enum.filter(fn aws_user -> !MapSet.member?(pocket_emails, aws_user["userName"]) end)
      |> Enum.each(&delete_from_aws/1)

      Logger.info("Reconciliation complete.")
    end
  end

  # --- API Fetchers ---

  defp fetch_pocket_id_users do
    url = "#{System.get_env("POCKET_ID_URL")}/api/users"
    headers = ["X-API-KEY": System.get_env("POCKETID_ADMIN_KEY")]

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

  defp fetch_aws_users do
    url = System.get_env("AWS_SCIM_ENDPOINT") <> "/Users"
    token = System.get_env("AWS_SCIM_TOKEN")

    # Note: AWS SCIM usually paginates. For small homelabs, the default (50) is usually enough.
    case Req.get(url, auth: {:bearer, token}) do
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

  defp upsert_to_aws(user) do
    email = user["email"]
    display_name = "#{user["firstName"]} #{user["lastName"]}"
    scim_url = System.get_env("AWS_SCIM_ENDPOINT") <> "/Users"
    token = System.get_env("AWS_SCIM_TOKEN")

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

    case Req.post(scim_url, json: body, auth: {:bearer, token}) do
      {:ok, %{status: 201}} -> Logger.info("Created user: #{email}")
      {:ok, %{status: 409}} -> Logger.debug("User exists: #{email}")
      error -> Logger.error("Failed upsert for #{email}: #{inspect(error)}")
    end
  end

  defp delete_from_aws(aws_user) do
    # SCIM Delete requires the AWS Internal ID, not the username
    id = aws_user["id"]
    email = aws_user["userName"]
    url = System.get_env("AWS_SCIM_ENDPOINT") <> "/Users/#{id}"
    token = System.get_env("AWS_SCIM_TOKEN")

    Logger.warn("Deleting stale user from AWS: #{email}")

    case Req.delete(url, auth: {:bearer, token}) do
      {:ok, %{status: 204}} -> Logger.info("Successfully deleted #{email}")
      error -> Logger.error("Failed to delete #{email}: #{inspect(error)}")
    end
  end

  defp schedule_sync(interval), do: Process.send_after(self(), :sync, interval)
end
