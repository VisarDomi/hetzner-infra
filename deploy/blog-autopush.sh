#!/usr/bin/env bash
#
# blog-autopush — commits and pushes blog changes if any exist.
# Runs daily via systemd timer. The deploy watcher picks up the push automatically.
#
set -euo pipefail

BLOG_REPO="$HOME/Documents/work/applications/blog"

cd "$BLOG_REPO"

# Check for any changes in content/posts/
if git diff --quiet content/posts/ && git diff --cached --quiet content/posts/ && [ -z "$(git ls-files --others --exclude-standard content/posts/)" ]; then
    echo "No blog changes to push"
    exit 0
fi

git add content/posts/
git commit -m "blog update $(date '+%Y-%m-%d')"
git push

echo "Pushed blog changes"
