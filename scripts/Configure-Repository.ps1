[CmdletBinding()]
param([string]$Repository = 'Electivus/caveman-npm', [string]$ReleaseApprover = 'manoelcalixto')
$ErrorActionPreference = 'Stop'
function Api([string]$Method, [string]$Path, $Body = $null) {
  if ($null -ne $Body) {
    $Result = ($Body | ConvertTo-Json -Depth 15 -Compress) | & gh api $Path --method $Method --input -
  } else { $Result = & gh api $Path --method $Method }
  if ($LASTEXITCODE -ne 0) { throw "GitHub API failed: $Method $Path" }
  if ($Result) { return ($Result | ConvertFrom-Json) }
}
$RepoPath = "repos/$Repository"
Api PATCH $RepoPath @{
  allow_merge_commit=$false; allow_rebase_merge=$false; allow_squash_merge=$true; delete_branch_on_merge=$true
  security_and_analysis=@{
    secret_scanning=@{status='enabled'}
    secret_scanning_push_protection=@{status='enabled'}
    secret_scanning_validity_checks=@{status='enabled'}
  }
} | Out-Null
Api PUT "$RepoPath/vulnerability-alerts" | Out-Null
Api PUT "$RepoPath/automated-security-fixes" | Out-Null
Api PUT "$RepoPath/private-vulnerability-reporting" | Out-Null
Api PUT "$RepoPath/actions/permissions/workflow" @{default_workflow_permissions='read';can_approve_pull_request_reviews=$false} | Out-Null
Api PUT "$RepoPath/actions/permissions" @{enabled=$true;allowed_actions='selected';sha_pinning_required=$true} | Out-Null
Api PUT "$RepoPath/actions/permissions/selected-actions" @{github_owned_allowed=$true;verified_allowed=$false;patterns_allowed=@()} | Out-Null

$Rules = @(
  @{
    name='Protect main'; target='branch'; enforcement='active'; bypass_actors=@()
    conditions=@{ref_name=@{include=@('refs/heads/main');exclude=@()}}
    rules=@(
      @{type='deletion'}, @{type='non_fast_forward'}, @{type='required_linear_history'},
      @{type='pull_request';parameters=@{required_approving_review_count=0;dismiss_stale_reviews_on_push=$true;require_code_owner_review=$false;require_last_push_approval=$false;required_review_thread_resolution=$true;allowed_merge_methods=@('squash')}},
      @{type='required_status_checks';parameters=@{strict_required_status_checks_policy=$true;do_not_enforce_on_create=$false;required_status_checks=@(@{context='windows';integration_id=15368})}}
    )
  },
  @{
    name='Protect release tags'; target='tag'; enforcement='active'; bypass_actors=@()
    conditions=@{ref_name=@{include=@('refs/tags/v*');exclude=@()}}
    rules=@(@{type='deletion'},@{type='non_fast_forward'})
  }
)
$Existing = @(Api GET "$RepoPath/rulesets")
foreach ($Rule in $Rules) {
  $Match = @($Existing | Where-Object { $_.name -eq $Rule.name })
  if ($Match.Count -gt 1) { throw "Duplicate ruleset: $($Rule.name)" }
  if ($Match.Count) { Api PUT "$RepoPath/rulesets/$($Match[0].id)" $Rule | Out-Null }
  else { Api POST "$RepoPath/rulesets" $Rule | Out-Null }
}
$Approver = Api GET "users/$ReleaseApprover"
Api PUT "$RepoPath/environments/npm-publish" @{
  wait_timer=0; prevent_self_review=$false; can_admins_bypass=$false
  reviewers=@(@{type='User';id=$Approver.id})
  deployment_branch_policy=@{protected_branches=$false;custom_branch_policies=$true}
} | Out-Null
$Policies = Api GET "$RepoPath/environments/npm-publish/deployment-branch-policies"
if (-not @($Policies.branch_policies | Where-Object { $_.name -eq 'v*' -and $_.type -eq 'tag' }).Count) {
  Api POST "$RepoPath/environments/npm-publish/deployment-branch-policies" @{name='v*';type='tag'} | Out-Null
}
Write-Host "Configured ${Repository}: protected main and version tags; read-only Actions defaults; SHA-pinned GitHub-owned Actions; secret scanning and push protection; Dependabot alerts/fixes; private reporting; release approval by $ReleaseApprover."
