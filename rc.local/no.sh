# read stdin, grep out all words on the command line

no() {
    # Usage: no [grep_flags] "word1" "word2" ...
    #
    # Example usage:
    # cat some_file.txt | no -i "word1" "word2"
    #
    #
    # Insipred by Marcus Ranum's "Artificial Ignornace":
    # https://www.ranum.com/security/computer_security/papers/ai/
    #
    # source this file to define the alias.

    local words=()
    local grep_flags=()

    # Separate grep flags from words
    while [ $# -gt 0 ]; do
        case "$1" in
            -*)
                # Argument is a flag (starts with -)
                grep_flags+=("$1")
                shift
                ;;
            *)
                # Argument is a word
                words+=("$1")
                shift
                ;;
        esac
    done

    # Construct a grep pattern that matches any of the given words
    local grep_pattern=""
    for word in "${words[@]}"; do
        if [ -n "$grep_pattern" ]; then
            grep_pattern="${grep_pattern}|${word}"
        else
            grep_pattern="${word}"
        fi
    done

    # Use grep with specified flags to filter out lines that contain
    # any of the specified words
    grep "${grep_flags[@]}" -Ev "($grep_pattern)"
}
