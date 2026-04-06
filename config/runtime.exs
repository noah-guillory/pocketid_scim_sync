import Config

config :pocketid_scim_sync,
  pocket_id_url: System.fetch_env!("POCKET_ID_URL"),
  pocket_id_admin_key: System.fetch_env!("POCKETID_ADMIN_KEY"),
  aws_scim_endpoint: System.fetch_env!("AWS_SCIM_ENDPOINT"),
  aws_scim_token: System.fetch_env!("AWS_SCIM_TOKEN")
