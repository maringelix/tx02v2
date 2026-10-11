# Generated secrets. Ephemeral resources are never stored in plan or state; their results are
# written only through write-only arguments (administrator_password_wo, value_wo) whose
# *_wo_version decides when a new value is sent. The same apply sends the same database password
# to the server and to the Key Vault secret.

ephemeral "random_password" "db" {
  length  = 40
  special = false
}

# Contract: 48 random alphanumeric characters.
ephemeral "random_password" "admin_token" {
  length  = 48
  special = false
}

locals {
  # Contract: JSON with string values username, password, host, port, dbname (ephemeral as well).
  db_secret_value = jsonencode({
    username = module.postgres.administrator_login
    password = ephemeral.random_password.db.result
    host     = module.postgres.fqdn
    port     = tostring(module.postgres.port)
    dbname   = module.postgres.database_name
  })
}
