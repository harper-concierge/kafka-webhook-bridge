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

# Wait for user input, and store it in a variable
# user_input=$(cat)
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

# Ask the user for input
printf "Please Specify a release Message which will be shared on Slack,  press Ctrl-D on a blank line when you're done:\n\n"
user_input=$(</dev/stdin)

#remove any weird control chars that might have ended up in the string
user_input=$(echo "$user_input" | tr -d '\001-\011\013\014\016-\037')

commit_message=$":bookmark: [ci skip] %s\n\n$user_input"
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

echo "New version has been released and tagged. CircleCI will handle the build and deployment."
