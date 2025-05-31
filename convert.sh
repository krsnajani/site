#!/bin/bash
# === convert.sh ===
# Description: Converts Markdown (.md), Org Mode (.org), or plain text (.txt) files
#              into HTML blog posts. It uses pandoc for conversion and wraps the
#              output with custom HTML header and footer templates.
#
# Usage: ./convert.sh <input_file>
#   - <input_file>: Path to the source file (.md, .org, or .txt).
#
# Dependencies:
#   - pandoc: Required for document conversion. Install if not present.
#   - Standard UNIX utilities (basename, head, tail, sed, awk, mktemp, grep).
#
# Templates:
#   - template_header.html: Must exist in the same directory as the script.
#                           Contains the HTML head, site navigation, and opening main content tags.
#                           Uses '{{TITLE}}' as a placeholder for the post title.
#                           CSS link is expected as '../style.css'.
#   - template_footer.html: Must exist in the same directory as the script.
#                           Contains closing main content tags and the site footer.
#
# Output:
#   - Generates an HTML file in the './posts/' directory (created if it doesn't exist).
#   - The output filename is the same as the input filename but with an .html extension
#     (e.g., input.md -> posts/input.html).
#
# Title Extraction Logic:
#   - .txt: First non-empty line of the file.
#   - .md/.org: Attempts to extract from pandoc's metadata (e.g., YAML front matter or #+TITLE).
#   - Fallback: If no title is found, it's generated from the input filename
#             (e.g., 'my-cool-post.md' becomes 'My Cool Post').
#
# Exit Codes:
#   - 0: Success
#   - 1: Error (e.g., file not found, pandoc missing, conversion failure)
#
# Author: Jules (AI Agent)
# Date: 2024-05-31 # Will be replaced by actual date if run through the user's sed command
#
# --- Script Starts Below ---

# --- Configuration ---
OUTPUT_DIR="posts"
TEMPLATE_HEADER="template_header.html"
TEMPLATE_FOOTER="template_footer.html"

# --- Helper Functions ---
print_usage() {
    echo "Usage: $0 <input_file>"
    echo "Converts .md, .org, or .txt files to HTML using pandoc and custom templates."
}

print_error() {
    echo "Error: $1" >&2
    exit 1
}

# --- Pre-flight Checks ---
# Check for pandoc
if ! command -v pandoc &> /dev/null; then
    print_error "pandoc could not be found. Please install pandoc."
fi

# Check for input file
if [ -z "$1" ]; then
    print_usage
    exit 1
fi

INPUT_FILE="$1"
if [ ! -f "$INPUT_FILE" ]; then
    print_error "Input file '$INPUT_FILE' not found."
fi

# Check for template files
if [ ! -f "$TEMPLATE_HEADER" ]; then
    print_error "Template header '$TEMPLATE_HEADER' not found."
fi
if [ ! -f "$TEMPLATE_FOOTER" ]; then
    print_error "Template footer '$TEMPLATE_FOOTER' not found."
fi

# --- File Processing ---
FILENAME_WITH_EXT=$(basename "$INPUT_FILE")
FILENAME_NO_EXT="${FILENAME_WITH_EXT%.*}"
FILE_EXT="${FILENAME_WITH_EXT##*.}"

# Create output directory if it doesn't exist
mkdir -p "$OUTPUT_DIR"
OUTPUT_FILE="$OUTPUT_DIR/$FILENAME_NO_EXT.html"

# --- Title Extraction ---
TITLE=""
PANDOC_INPUT_CONTENT="$INPUT_FILE" # Default to using the file directly

if [ "$FILE_EXT" = "txt" ]; then
    # For .txt, use the first non-empty line as title and the rest as content
    TITLE=$(head -n 1 "$INPUT_FILE" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
    # Prepare content without the first line for pandoc
    TEMP_CONTENT_FILE=$(mktemp)
    tail -n +2 "$INPUT_FILE" > "$TEMP_CONTENT_FILE"
    PANDOC_INPUT_CONTENT="$TEMP_CONTENT_FILE"
    PANDOC_FORMAT="commonmark" # Or "plain" - commonmark might give better paragraph handling
else
    # For .md and .org, try to get title from metadata using pandoc
    # This extracts title from pandoc's HTML output of a standalone page
    # Explicitly set format for pandoc
    if [ "$FILE_EXT" = "md" ]; then
        DETECTED_PANDOC_FORMAT="markdown"
    elif [ "$FILE_EXT" = "org" ]; then
        DETECTED_PANDOC_FORMAT="org"
    else
        DETECTED_PANDOC_FORMAT="$FILE_EXT" # Fallback, though we primarily expect md, org, txt
    fi
    TITLE=$(pandoc --standalone --from "$DETECTED_PANDOC_FORMAT" --to html5 "$INPUT_FILE" | grep -oP '<title>\K[^<]+' || true)
    PANDOC_FORMAT="$DETECTED_PANDOC_FORMAT"
fi

# Fallback title if extraction failed or empty
if [ -z "$TITLE" ]; then
    # Capitalize first letter of each word in filename, replace hyphens with spaces
    TITLE=$(echo "$FILENAME_NO_EXT" | sed -e 's/-/ /g' -e 's/\b\(.\)/\u\1/g')
fi


# --- Pandoc Conversion (Body Only) ---
HTML_BODY=$(pandoc --from "$PANDOC_FORMAT" --to html5 "$PANDOC_INPUT_CONTENT")

# Clean up temp file for .txt
if [ "$FILE_EXT" = "txt" ] && [ -f "$TEMP_CONTENT_FILE" ]; then
    rm "$TEMP_CONTENT_FILE"
fi

# Check for pandoc conversion error after trying to get HTML_BODY
if [ $? -ne 0 ] || [ -z "$HTML_BODY" ]; then
    # If HTML_BODY is empty, it might also indicate a pandoc issue not caught by $?
    print_error "Pandoc conversion failed or produced empty output for '$INPUT_FILE'."
fi

# --- HTML Assembly ---
# Prepare header: Read template and replace {{TITLE}}
# Using awk for safer title replacement to avoid issues if title contains slashes or ampersands
PROCESSED_HEADER=$(awk -v title="$TITLE" '{gsub(/{{TITLE}}/, title)}1' "$TEMPLATE_HEADER")

# Combine header, body, and footer
echo "$PROCESSED_HEADER" > "$OUTPUT_FILE"
echo "$HTML_BODY" >> "$OUTPUT_FILE"
cat "$TEMPLATE_FOOTER" >> "$OUTPUT_FILE"

# --- Final Steps ---
# No need to chmod +x $0 here, do it once after file creation by the subtask runner.

echo "Successfully converted '$INPUT_FILE' to '$OUTPUT_FILE'"
echo "Title used: $TITLE"

exit 0
