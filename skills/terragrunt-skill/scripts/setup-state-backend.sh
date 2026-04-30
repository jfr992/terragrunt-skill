#!/bin/bash
#
# Create S3 buckets and DynamoDB tables for Terragrunt/OpenTofu state management.
#
# This script automatically discovers accounts, regions, and environments from the
# directory structure and creates the appropriate state buckets and lock tables.
#
# Usage:
#   ./setup-state-backend.sh [OPTIONS]
#
# Options:
#   -d, --dry-run       Show what would be created without creating
#   -a, --account NAME  Process only specific account
#   -h, --help          Show this help

set -e

usage() {
    cat << EOF
Usage: $(basename "$0") [OPTIONS]

Create S3 buckets and DynamoDB tables for Terragrunt/OpenTofu state management.

OPTIONS:
    -d, --dry-run       Show what would be created without creating
    -a, --account NAME  Process only specific account
    -h, --help          Show this help

EXAMPLES:
    # Create all state backends
    $(basename "$0")

    # Dry run
    $(basename "$0") --dry-run

    # Only specific account
    $(basename "$0") --account prod

EOF
    exit 0
}

log() {
    echo "[$(date +'%H:%M:%S')] $*"
}

parse_hcl() {
    local file=$1
    local key=$2

    local value=$(grep -A 100 "locals[[:space:]]*{" "$file" 2>/dev/null | \
                  grep "[[:space:]]*${key}[[:space:]]*=" | \
                  head -n1 | \
                  sed -E "s/.*${key}[[:space:]]*=[[:space:]]*\"?([^\"#]*).*/\1/" | \
                  tr -d '"' | sed 's/[[:space:]]*$//')

    if [[ "$value" == "local.environment" ]]; then
        value=$(grep -A 100 "locals[[:space:]]*{" "$file" 2>/dev/null | \
                grep "[[:space:]]*environment[[:space:]]*=" | \
                head -n1 | \
                sed -E "s/.*environment[[:space:]]*=[[:space:]]*\"?([^\"#]*).*/\1/" | \
                tr -d '"' | sed 's/[[:space:]]*$//')
    fi

    echo "$value"
}

create_bucket() {
    local bucket=$1
    local region=$2
    local account_id=$3
    local dry_run=$4

    if [[ "$dry_run" == "true" ]]; then
        echo "  [DRY RUN] Would create bucket: $bucket"
        return
    fi

    if aws s3api head-bucket --bucket "$bucket" 2>/dev/null; then
        log "Bucket already exists: $bucket - skipping"
        return
    fi

    log "Creating bucket: $bucket"

    if [[ "$region" == "us-east-1" ]]; then
        aws s3api create-bucket --bucket "$bucket" --region "$region"
    else
        aws s3api create-bucket --bucket "$bucket" --region "$region" \
            --create-bucket-configuration LocationConstraint="$region"
    fi

    aws s3api put-bucket-versioning --bucket "$bucket" \
        --versioning-configuration Status=Enabled

    aws s3api put-bucket-encryption --bucket "$bucket" \
        --server-side-encryption-configuration '{
            "Rules": [{
                "ApplyServerSideEncryptionByDefault": {
                    "SSEAlgorithm": "aws:kms",
                    "KMSMasterKeyID": "alias/aws/s3"
                },
                "BucketKeyEnabled": true
            }]
        }'

    aws s3api put-public-access-block --bucket "$bucket" \
        --public-access-block-configuration \
            "BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true"

    aws s3api put-bucket-policy --bucket "$bucket" --policy "{
        \"Version\": \"2012-10-17\",
        \"Statement\": [
            {
                \"Sid\": \"EnforcedTLS\",
                \"Effect\": \"Deny\",
                \"Principal\": \"*\",
                \"Action\": \"s3:*\",
                \"Resource\": [
                    \"arn:aws:s3:::${bucket}\",
                    \"arn:aws:s3:::${bucket}/*\"
                ],
                \"Condition\": {
                    \"Bool\": {
                        \"aws:SecureTransport\": \"false\"
                    }
                }
            },
            {
                \"Sid\": \"RootAccess\",
                \"Effect\": \"Allow\",
                \"Principal\": {
                    \"AWS\": \"arn:aws:iam::${account_id}:root\"
                },
                \"Action\": \"s3:*\",
                \"Resource\": [
                    \"arn:aws:s3:::${bucket}\",
                    \"arn:aws:s3:::${bucket}/*\"
                ]
            }
        ]
    }"
}

create_table() {
    local table=$1
    local region=$2
    local account_id=$3
    local dry_run=$4

    if [[ "$dry_run" == "true" ]]; then
        echo "  [DRY RUN] Would create table: $table"
        return
    fi

    if aws dynamodb describe-table --table-name "$table" --region "$region" 2>/dev/null >/dev/null; then
        log "Table already exists: $table - skipping"
        return
    fi

    log "Creating table: $table"

    aws dynamodb create-table \
        --table-name "$table" \
        --attribute-definitions AttributeName=LockID,AttributeType=S \
        --key-schema AttributeName=LockID,KeyType=HASH \
        --billing-mode PAY_PER_REQUEST \
        --region "$region"

    aws dynamodb wait table-exists --table-name "$table" --region "$region"
}

main() {
    local dry_run="false"
    local filter_account=""

    while [[ $# -gt 0 ]]; do
        case $1 in
            -d|--dry-run) dry_run="true"; shift ;;
            -a|--account) filter_account="$2"; shift 2 ;;
            -h|--help) usage ;;
            *) echo "Unknown option: $1"; exit 1 ;;
        esac
    done

    [[ "$dry_run" == "true" ]] && log "DRY RUN MODE"

    for account_dir in */; do
        [[ ! -f "$account_dir/account.hcl" ]] && continue

        local account=$(basename "$account_dir")
        [[ -n "$filter_account" && "$account" != "$filter_account" ]] && continue

        local account_name=$(parse_hcl "$account_dir/account.hcl" "account_name")
        local aws_account_id=$(parse_hcl "$account_dir/account.hcl" "aws_account_id")
        [[ -z "$account_name" ]] && continue
        [[ -z "$aws_account_id" ]] && continue

        log "Processing account: $account ($account_name)"

        for region_dir in "$account_dir"*/; do
            [[ ! -d "$region_dir" ]] && continue

            local region=$(basename "$region_dir")
            [[ ! "$region" =~ ^(us|eu|ap|ca|sa|me|af)- ]] && continue

            for env_dir in "$region_dir"*/; do
                [[ ! -d "$env_dir" ]] && continue
                [[ ! -f "$env_dir/env.hcl" && ! -f "$env_dir/terragrunt.hcl" ]] && continue

                local env=$(basename "$env_dir")
                local suffix=$(parse_hcl "$env_dir/env.hcl" "state_bucket_suffix")

                local bucket table
                if [[ -n "$suffix" ]]; then
                    bucket="tfstate-${account_name}-${suffix}-${region}"
                    table="tfstate-locks-${account_name}-${suffix}-${region}"
                    log "$account/$region/$env -> with suffix: $suffix"
                else
                    bucket="tfstate-${account_name}-${region}"
                    table="tfstate-locks-${account_name}-${region}"
                    log "$account/$region/$env -> no suffix"
                fi

                echo ""
                create_bucket "$bucket" "$region" "$aws_account_id" "$dry_run"
                create_table "$table" "$region" "$aws_account_id" "$dry_run"
            done

            if [[ -f "$region_dir/env.hcl" ]]; then
                local suffix=$(parse_hcl "$region_dir/env.hcl" "state_bucket_suffix")

                local bucket table
                if [[ -n "$suffix" ]]; then
                    bucket="tfstate-${account_name}-${suffix}-${region}"
                    table="tfstate-locks-${account_name}-${suffix}-${region}"
                    log "$account/$region -> with suffix: $suffix"
                else
                    bucket="tfstate-${account_name}-${region}"
                    table="tfstate-locks-${account_name}-${region}"
                    log "$account/$region -> no suffix"
                fi

                echo ""
                create_bucket "$bucket" "$region" "$aws_account_id" "$dry_run"
                create_table "$table" "$region" "$aws_account_id" "$dry_run"
            fi
        done
    done

    echo ""
    log "Done!"
}

for tool in aws grep sed; do
    command -v "$tool" >/dev/null || { echo "Error: $tool required"; exit 1; }
done

main "$@"
