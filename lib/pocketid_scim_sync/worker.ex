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
    Logger.info("Starting SCIM synchronization...")

    with {:ok, users} <- fetch_pocket_id_users() do
      Enum.each(users, &upsert_to_aws/1)
    end
  end

  defp fetch_pocket_id_users do
    url = "#{System.get_env("POCKET_ID_URL")}/api/users"
    headers = ["X-API-KEY": "#{System.get_env("POCKETID_ADMIN_KEY")}"]

    case Req.get(url, headers: headers) do
      # Notice we match on %{"data" => users} now
      {:ok, %{status: 200, body: %{"data" => users}}} ->
        {:ok, users}

      {:ok, %{status: status, body: body}} ->
        Logger.error("PocketID returned status #{status}: #{inspect(body)}")
        :error

      {:error, error} ->
        Logger.error("Failed to fetch PocketID users: #{inspect(error)}")
        :error
    end
  end

  defp upsert_to_aws(user) do
    # Pulling values once for clarity
    email = user["email"]
    display_name = "#{user["firstName"]} #{user["lastName"]}"

    scim_url = System.get_env("AWS_SCIM_ENDPOINT") <> "/Users"
    token = System.get_env("AWS_SCIM_TOKEN")

    Logger.info("Syncing user to AWS: #{email} (#{display_name})")

    body = %{
      schemas: ["urn:ietf:params:scim:schemas:core:2.0:User"],
      userName: email,
      displayName: display_name,
      # --- Add this block ---
      name: %{
        formatted: display_name,
        givenName: user["firstName"],
        familyName: user["lastName"]
      },
      # ----------------------
      emails: [%{value: email, primary: true, type: "work"}],
      active: true
    }

    case Req.post(scim_url, json: body, auth: {:bearer, token}) do
      {:ok, %{status: 201}} ->
        Logger.info("Successfully created user in AWS: #{email}")

      {:ok, %{status: 409}} ->
        Logger.debug("User already exists in AWS: #{email} (Skipping creation)")

      {:ok, %{status: status, body: body}} ->
        Logger.error(
          "AWS SCIM returned unexpected status #{status} for #{email}: #{inspect(body)}"
        )

      {:error, error} ->
        Logger.error("Network error syncing #{email} to AWS: #{inspect(error)}")
    end
  end

  defp schedule_sync(interval), do: Process.send_after(self(), :sync, interval)
end
