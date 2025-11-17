output "powerdns_api_key" {
  description = "Generated PowerDNS API key"
  value       = random_password.powerdns_api_key.result
  sensitive   = true
}