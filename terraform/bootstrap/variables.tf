variable "subscription_id" {
  description = "ID of the dedicated subscription of the lab (the bootstrap never guesses it)."
  type        = string

  validation {
    condition     = can(regex("^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$", var.subscription_id))
    error_message = "The subscription_id must be a lowercase GUID (az account show --query id -o tsv)."
  }
}

variable "location" {
  description = "Azure location of the bootstrap and lab resource groups (must match the lab location)."
  type        = string
  default     = "eastus2"

  validation {
    condition     = can(regex("^[a-z][a-z0-9]{2,30}$", var.location))
    error_message = "The location must be an Azure location name such as eastus2 or brazilsouth."
  }
}

variable "github_owner" {
  description = "GitHub owner of the tx02v2 and dx02v2 repositories (federated credential subjects). No default: the identities trust only the repositories of this owner, so a fork must name its own."
  type        = string

  validation {
    condition     = can(regex("^[A-Za-z0-9](?:[A-Za-z0-9-]{0,38})$", var.github_owner))
    error_message = "The github_owner must be a valid GitHub user or organization name."
  }

  validation {
    condition     = lower(var.github_owner) != "your-github-user"
    error_message = "Set github_owner to the GitHub user that owns your forks (terraform.tfvars.example holds a placeholder)."
  }
}

variable "state_protection_lock" {
  description = "CanNotDelete lock on the state storage account (set false only for the final teardown)."
  type        = bool
  default     = true
}

variable "monthly_budget_amount" {
  description = "Monthly cost budget of the subscription, in its billing currency."
  type        = number
  default     = 25

  validation {
    condition     = var.monthly_budget_amount >= 1 && var.monthly_budget_amount <= 1000
    error_message = "The monthly_budget_amount must be between 1 and 1000."
  }
}

variable "budget_alert_emails" {
  description = "E-mail addresses that receive the budget alerts (1-10)."
  type        = list(string)

  validation {
    condition     = length(var.budget_alert_emails) >= 1 && length(var.budget_alert_emails) <= 10
    error_message = "Set between 1 and 10 addresses in budget_alert_emails."
  }

  validation {
    condition     = alltrue([for e in var.budget_alert_emails : can(regex("^[A-Za-z0-9._%+-]+@[A-Za-z0-9-]+(\\.[A-Za-z0-9-]+)*\\.[A-Za-z]{2,}$", e))])
    error_message = "Every budget_alert_emails entry must be a valid e-mail address, e.g. you@example.com."
  }

  validation {
    condition     = !contains([for e in var.budget_alert_emails : lower(e)], "you@example.com")
    error_message = "Replace the placeholder you@example.com of terraform.tfvars.example with an address you read: the budget alerts are the only warning of a forgotten lab."
  }
}
