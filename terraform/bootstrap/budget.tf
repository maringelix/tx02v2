# Subscription-wide monthly cost budget (use a dedicated subscription for the lab). Amounts are in
# the billing currency of the subscription. Azure requires the start date to be the first day of
# a month: the first apply takes the current month and later plans ignore it (no perpetual diff).

locals {
  budget_notifications = {
    "actual-50"      = { threshold_type = "Actual", threshold = 50 }
    "actual-80"      = { threshold_type = "Actual", threshold = 80 }
    "actual-100"     = { threshold_type = "Actual", threshold = 100 }
    "forecasted-100" = { threshold_type = "Forecasted", threshold = 100 }
  }
}

resource "azurerm_consumption_budget_subscription" "monthly" {
  name            = "${local.project}-monthly"
  subscription_id = "/subscriptions/${var.subscription_id}"
  amount          = var.monthly_budget_amount
  time_grain      = "Monthly"

  time_period {
    start_date = formatdate("YYYY-MM-01'T'00:00:00Z", plantimestamp())
  }

  dynamic "notification" {
    for_each = local.budget_notifications

    content {
      enabled        = true
      operator       = "GreaterThan"
      threshold      = notification.value.threshold
      threshold_type = notification.value.threshold_type
      contact_emails = var.budget_alert_emails
    }
  }

  lifecycle {
    ignore_changes = [time_period]
  }
}
