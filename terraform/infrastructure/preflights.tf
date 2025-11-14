# Pre-flight validation checks embedded in Terraform
# These run as part of terraform plan/apply and block deployment if failed

# Check 1: Ensure git tree is clean (matches Flux behavior)
data "external" "git_status_check" {
  program = ["bash", "-c", <<-EOF
    cd "${path.module}/../.."

    # Check for uncommitted changes (excluding .md files)
    if ! git diff --quiet -- ':!*.md' || ! git diff --cached --quiet -- ':!*.md'; then
      echo '{"error": "Git tree is dirty - uncommitted changes detected. Flux would not deploy with uncommitted changes. Please commit first."}' >&2
      exit 1
    fi

    # Warn about untracked files but don't fail
    untracked=$(git ls-files --others --exclude-standard)
    if [[ -n "$untracked" ]]; then
      echo '{"status": "clean", "warning": "untracked_files_detected"}'
    else
      echo '{"status": "clean", "warning": "none"}'
    fi
    EOF
  ]
}

# Check 2: Run pre-commit validation
data "external" "precommit_validation" {
  program = ["bash", "-c", <<-EOF
    cd "${path.module}/../.."

    # Run pre-commit on all files
    if ! pre-commit run --all-files >/dev/null 2>&1; then
      echo '{"error": "Pre-commit validation failed. Please run: pre-commit run --all-files"}' >&2
      exit 1
    fi

    echo '{"status": "passed"}'
    EOF
  ]

  depends_on = [data.external.git_status_check]
}

# Check 3: Validate kustomizations in parallel
data "external" "kustomize_validation" {
  program = ["python3", "${path.module}/../../scripts/validate-kustomizations.py", "--format=json", "--root=${path.module}/../../k8s/"]

  depends_on = [data.external.precommit_validation]
}

# Display validation summary
resource "null_resource" "preflight_summary" {
  triggers = {
    git_status       = data.external.git_status_check.result.status
    precommit_status = data.external.precommit_validation.result.status
    kustomize_status = data.external.kustomize_validation.result.status
  }

  provisioner "local-exec" {
    command = <<-EOF
      echo "🛡️  Pre-flight validation completed:"
      echo "  ✅ Git tree: ${data.external.git_status_check.result.status}"
      echo "  ✅ Pre-commit: ${data.external.precommit_validation.result.status}"
      echo "  ✅ Kustomizations: ${data.external.kustomize_validation.result.status}"
    EOF
  }
}