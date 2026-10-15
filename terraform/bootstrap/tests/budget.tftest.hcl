# Subscription budget (cost guardrail) and its input validation.

mock_provider "azurerm" {
  source = "../tests/mocks"
}

variables {
  github_owner         = "maringelix"
  github_owner_id      = "1000000"
  tx02v2_repository_id = "2000000"
  dx02v2_repository_id = "3000000"
  subscription_id      = "00000000-0000-0000-0000-000000000000"
  budget_alert_emails  = ["lab-alerts@example.org", "ops@example.org"]
}

run "monthly_budget_with_four_alerts" {
  command = plan

  assert {
    condition     = azurerm_consumption_budget_subscription.monthly.subscription_id == "/subscriptions/00000000-0000-0000-0000-000000000000" && azurerm_consumption_budget_subscription.monthly.time_grain == "Monthly"
    error_message = "The budget must be a monthly budget of the whole subscription."
  }

  assert {
    condition     = azurerm_consumption_budget_subscription.monthly.amount == 25
    error_message = "The default amount must be 25 (billing currency)."
  }

  assert {
    condition = toset([for n in azurerm_consumption_budget_subscription.monthly.notification : "${n.threshold_type}:${n.threshold}"]) == toset([
      "Actual:50",
      "Actual:80",
      "Actual:100",
      "Forecasted:100",
    ])
    error_message = "Notifications must be Actual 50/80/100 % and Forecasted 100 %."
  }

  assert {
    condition = alltrue([
      for n in azurerm_consumption_budget_subscription.monthly.notification :
      n.enabled && n.operator == "GreaterThan" && n.contact_emails == tolist(["lab-alerts@example.org", "ops@example.org"])
    ])
    error_message = "Every notification must be enabled, GreaterThan and sent to all budget_alert_emails."
  }

  assert {
    condition     = can(regex("^[0-9]{4}-[0-9]{2}-01T00:00:00Z$", azurerm_consumption_budget_subscription.monthly.time_period[0].start_date))
    error_message = "The start date must be the first day of a month (Azure requirement)."
  }

  assert {
    condition     = azurerm_consumption_budget_subscription.monthly.time_period[0].start_date == formatdate("YYYY-MM-01'T'00:00:00Z", plantimestamp())
    error_message = "The first apply takes the current month (ignore_changes keeps it afterwards)."
  }
}

run "budget_amount_is_configurable" {
  command = plan

  variables {
    monthly_budget_amount = 10.5
  }

  assert {
    condition     = azurerm_consumption_budget_subscription.monthly.amount == 10.5
    error_message = "monthly_budget_amount must reach the budget."
  }
}

run "rejects_an_invalid_email" {
  command = plan

  variables {
    budget_alert_emails = ["not-an-email"]
  }

  expect_failures = [var.budget_alert_emails]
}

run "rejects_an_empty_email_list" {
  command = plan

  variables {
    budget_alert_emails = []
  }

  expect_failures = [var.budget_alert_emails]
}

run "rejects_a_budget_below_one" {
  command = plan

  variables {
    monthly_budget_amount = 0
  }

  expect_failures = [var.monthly_budget_amount]
}

run "placeholder_alert_email_is_refused" {
  command = plan

  variables {
    budget_alert_emails = ["YOU@example.com"]
  }

  expect_failures = [var.budget_alert_emails]
}
