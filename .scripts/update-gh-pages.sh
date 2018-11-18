#!/bin/bash -e

ORG="tmandry"
NAME="Swindler"
CHECKOUT_PATH="docs/output/gh-pages"
DOC_URL_ROOT="docs"
SITE_URL="https://$ORG.github.io/$NAME"

RELEASE="$1"
SHA=`git rev-parse HEAD`
REPO=`git config remote.origin.url`

RELEASE="$TRAVIS_BRANCH"
PERMALINK="$SHA"
if [ "$TRAVIS_TAG" != "" ]; then
    RELEASE="$TRAVIS_TAG"
    PERMALINK="$TRAVIS_TAG"
fi

if [ "$RELEASE" == "" ]; then exit 1; fi
if [ "$GITHUB_TOKEN" == "" ]; then exit 2; fi

rm -rf "$CHECKOUT_PATH"
git clone --branch gh-pages "$REPO" "$CHECKOUT_PATH"

TARGET_DIR="$DOC_URL_ROOT/$RELEASE"

echo " ==> Installing jazzy"
gem install jazzy --no-rdoc --no-ri

echo " ==> Generating docs"
jazzy \
    --clean \
    --output "$CHECKOUT_PATH/$TARGET_DIR" \
    --github_file_prefix "https://github.com/$ORG/$NAME/blob/$PERMALINK" \
    --root-url "$SITE_URL/$TARGET_DIR"

pushd "$CHECKOUT_PATH"

    git config user.name "Deployment Bot"
    git config user.email "deploy@travis-ci.org"

    CHANGE_SET=$(git status -s)
    if [ "$CHANGE_SET" == "" ]; then
        echo "No doc changes present; exiting."
        exit 0
    fi

    echo " ==> Deploying docs"
    set -x

    git add -A "$TARGET_DIR"
    git commit -m "[$RELEASE] Regenerate docs"
    git push -q "https://$GITHUB_TOKEN@github.com/$ORG/$NAME.git" gh-pages

popd

echo " ==> Docs updated at $SITE_URL/$TARGET_DIR"
