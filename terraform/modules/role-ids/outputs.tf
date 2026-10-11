output "lab_assignable" {
  description = "Map role name => role definition GUID of every role the lab root may assign."
  value       = local.lab_assignable
}
