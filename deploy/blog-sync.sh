#!/usr/bin/env bash
#
# blog-sync — copies raw markdown notes into the Hugo blog repo, adds front matter, commits, and pushes.
#
# Raw notes go in:   ~/Documents/blog/*.md
# Hugo posts go in:  ~/Documents/wip/hetzner/blog/content/posts/
#
# Front matter conversion:
#   # Title            → title: "Title"
#   **Date:** YYYY-MM-DD → date: YYYY-MM-DD
#   First paragraph    → summary (truncated to 120 chars)
#
# Already-converted posts (with --- front matter) are skipped.
# After syncing, commits and pushes the blog repo. The watcher handles deployment.
#
set -euo pipefail

NOTES_DIR="$HOME/Documents/blog"
BLOG_REPO="$HOME/Documents/wip/hetzner/blog"
POSTS_DIR="$BLOG_REPO/content/posts"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"
}

synced=0

for note in "$NOTES_DIR"/*.md; do
    [[ -f "$note" ]] || continue

    filename=$(basename "$note")
    target="$POSTS_DIR/$filename"

    # Skip if already in the Hugo repo
    if [[ -f "$target" ]]; then
        continue
    fi

    log "Syncing $filename..."

    # Check if the note already has YAML front matter
    if head -1 "$note" | grep -q '^---$'; then
        cp "$note" "$target"
        synced=$((synced + 1))
        continue
    fi

    # Extract title from first # heading
    title=$(grep -m1 '^# ' "$note" | sed 's/^# //')

    # Extract date from **Date:** line
    post_date=$(grep -m1 '^\*\*Date:\*\*' "$note" | sed 's/.*\*\*Date:\*\* *//')

    # Generate summary from first real paragraph (skip title, date, blank lines)
    summary=$(awk '
        /^# / { next }
        /^\*\*Date:\*\*/ { next }
        /^$/ { if (!found) next; else exit }
        /^## / { if (!found) next; else exit }
        { found=1; printf "%s ", $0 }
    ' "$note" | head -c 120 | sed 's/ *$//')

    # Build the Hugo post: front matter + content (without title and date lines)
    {
        echo "---"
        echo "title: \"$(echo "$title" | sed 's/"/\\"/g')\""
        echo "date: $post_date"
        [[ -n "$summary" ]] && echo "summary: \"$(echo "$summary" | sed 's/"/\\"/g')\""
        echo "---"
        # Strip the title line and date line from the body
        awk '
            NR == 1 && /^# / { next }
            /^\*\*Date:\*\*/ { next }
            # Skip blank line right after date
            prev_date && /^$/ { prev_date=0; next }
            /^\*\*Date:\*\*/ { prev_date=1; next }
            { print }
        ' "$note"
    } > "$target"

    synced=$((synced + 1))
done

if [[ "$synced" -eq 0 ]]; then
    log "No new notes to sync"
    exit 0
fi

log "Synced $synced note(s), committing..."

cd "$BLOG_REPO"
git add content/posts/
git commit -m "Add $synced new post(s) from notes

Co-Authored-By: blog-sync <noreply@veron3.space>"
git push

log "Pushed. Watcher will deploy on next cycle."
