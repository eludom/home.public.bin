all() {
    # read stdin, grep, include lines containing all words on the command line
    #
    # Usage: all [grep_flags] "word1" "word2" ...
    #
    # Example usage:
    # cat some_file.txt | all -i "word1" "word2"
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

    # Construct a grep pattern that matches all the given words
    local command="grep ${grep_flags[@]} -E ${words[0]}"
    for ((i=1; i<${#words[@]}; i++)); do
      command+=" | grep ${grep_flags[@]} -E ${words[i]}"
    done

    eval $command
}
