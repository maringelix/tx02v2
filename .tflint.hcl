# tflint configuration used by scripts/harness.sh (tflint --recursive from terraform/).
# The azurerm plugin is installed by scripts/install-tools.sh (SHA256-verified) into
# .tools/tflint-plugins, so `tflint --init` is never needed. Keep `version` equal to
# TFLINT_RULESET_AZURERM_VERSION in tools/versions.env (checked by the harness).

config {
  call_module_type = "local"
}

plugin "terraform" {
  enabled = true
  preset  = "recommended"
}

plugin "azurerm" {
  enabled = true
  version = "0.32.0"
  source  = "github.com/terraform-linters/tflint-ruleset-azurerm"
}
