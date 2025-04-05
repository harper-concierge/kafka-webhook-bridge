#!/usr/bin/env bash
set -o errexit

sanitize() {
    echo "$1" | tr '[:upper:]' '[:lower:]' | sed -e 's/[^a-zA-Z0-9]/-/g'
}

git fetch --tags

# Get the current version from package.json
CURRENT_VERSION=$(node -p "require('./package.json').version")

# Get the current git branch
CURRENT_BRANCH=$(git symbolic-ref --short HEAD)

# Extract the branch name after "feature/"
BRANCH_NAME=${CURRENT_BRANCH#feature/}

# Sanitize the branch name
BRANCH_NAME=$(sanitize "$BRANCH_NAME")

patch='patch'

if [ "$1" ]; then
    if [ "$1" != "major" ] && [ "$1" != "minor" ] && [ "$1" != "patch" ]; then
        # $1 could be a version string like "v3.1.2"
        if [ "v$CURRENT_VERSION" == "$1" ]; then
            echo "This will deploy the current Version $CURRENT_VERSION to production"
        else
            echo "The current Version '$CURRENT_VERSION' does not match the supplied version '$1'. Exiting"
            exit 1
        fi
    else
        patch=$1
    fi
fi

commit_message=$":bookmark: [ci skip] %s"
# Check if the current branch begins with "feature/"
if [[ $CURRENT_BRANCH == feature/* ]]; then
    if [ "v$CURRENT_VERSION" == "$1" ]; then
        #Don't increment version, just tag for live
        echo "Tagging Feature branch for production deployment!"
        # shellcheck disable=SC2059
        git tag -a "$1" -m "$(printf "%b" "$(printf "$commit_message" "$1")")"

    else
        npm version "$patch" --no-git-tag-version
        # Get the new version from package.json
        NEW_VERSION=$(node -p "require('./package.json').version")
        git add package.json package-lock.json
        # shellcheck disable=SC2059
        git commit -m "$(printf "%b" "$(printf "$commit_message" "$NEW_VERSION")")"

        echo
        echo "Tagging $NEW_VERSION for staging as v${NEW_VERSION}-staging"
        echo
        # Create a git tag with the custom name
        git tag "v${NEW_VERSION}-staging"
    fi

else
    echo "Releasing a new $patch version."
    npm version "$patch" -m "$(printf "%b" "$commit_message")"
fi

git push origin --follow-tags

echo "New version has been released and tagged. CircleCI will handle the build and upload to ECR. You need to deploy manually"
