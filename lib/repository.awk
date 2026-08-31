# Parse and print repository configuration.
#
# Input forms:
#   git NAME SOURCE [PRIORITY]
#   dir NAME ABSOLUTE_PATH [PRIORITY]
#   repo NAME ABSOLUTE_PATH [PRIORITY]   (compatibility alias for dir)
#
# Normalized records are tab-separated:
#   KIND NAME SOURCE CHECKOUT PRIORITY ORDER

function repository_trim(value) {
    sub(/^[ \t]+/, "", value)
    sub(/[ \t]+$/, "", value)
    return value
}

function repository_stderr(message,    command) {
    command = "cat >&2"
    print message | command
    close(command)
}

function repository_error(message) {
    repository_stderr((program == "" ? "src" : program) ": " message)
    repository_failed = 1
}

{
    repository_line = $0
    sub(/\r$/, "", repository_line)
    sub(/[ \t]*#.*/, "", repository_line)
    repository_line = repository_trim(repository_line)
    if (repository_line == "")
        next

    repository_count_fields = split(repository_line, repository_fields,
                                    /[ \t]+/)
    repository_kind = repository_fields[1]
    if (repository_kind == "repo")
        repository_kind = "dir"
    if (repository_count_fields < 3 || repository_count_fields > 4 ||
        (repository_kind != "git" && repository_kind != "dir")) {
        repository_error(FILENAME ":" FNR \
                         ": expected 'git NAME SOURCE [PRIORITY]' or " \
                         "'dir NAME ABSOLUTE_PATH [PRIORITY]'")
        next
    }

    repository_name = repository_fields[2]
    repository_source = repository_fields[3]
    repository_priority = repository_count_fields == 4 \
                          ? repository_fields[4] : 0

    if (repository_name !~ /^[[:alnum:]][[:alnum:].+_-]*$/) {
        repository_error(FILENAME ":" FNR ": invalid repository name '" \
                         repository_name "'")
        next
    }
    if (repository_source == "" || repository_source ~ /[[:cntrl:]]/) {
        repository_error(FILENAME ":" FNR ": invalid source for repository '" \
                         repository_name "'")
        next
    }
    if (repository_kind == "dir" && repository_source !~ /^\//) {
        repository_error(FILENAME ":" FNR ": directory repository '" \
                         repository_name "' requires an absolute path")
        next
    }
    if (repository_kind == "git" && substr(repository_source, 1, 1) == "-") {
        repository_error(FILENAME ":" FNR ": invalid Git source for repository '" \
                         repository_name "'")
        next
    }
    repository_source_lower = tolower(repository_source)
    if (repository_kind == "git" &&
        repository_source_lower ~ /^https?:\/\/[^\/]*@/) {
        repository_error(FILENAME ":" FNR \
                         ": credential-bearing HTTP(S) Git source is not permitted for repository '" \
                         repository_name "'")
        next
    }
    if (repository_priority !~ /^-?[[:digit:]]+$/) {
        repository_error(FILENAME ":" FNR ": invalid priority '" \
                         repository_priority "'")
        next
    }
    repository_priority_number = repository_priority + 0
    if (repository_priority_number < -2147483648 ||
        repository_priority_number > 2147483647) {
        repository_error(FILENAME ":" FNR ": priority out of range '" \
                         repository_priority "'")
        next
    }
    if (repository_seen[repository_name]) {
        repository_error(FILENAME ":" FNR ": duplicate repository '" \
                         repository_name "'")
        next
    }

    if (repository_kind == "git") {
        if (repo_root !~ /^\// || repo_root ~ /[[:cntrl:]]/) {
            repository_error("invalid Git repository checkout root '" \
                             repo_root "'")
            next
        }
        repository_checkout = repo_root == "/" \
                              ? "/" repository_name \
                              : repo_root "/" repository_name
    } else {
        repository_checkout = repository_source
    }

    repository_seen[repository_name] = 1
    repository_total++
    repository_kinds[repository_total] = repository_kind
    repository_names[repository_total] = repository_name
    repository_sources[repository_total] = repository_source
    repository_checkouts[repository_total] = repository_checkout
    repository_priorities[repository_total] = repository_priority_number
}

END {
    if (repository_failed)
        exit 2

    OFS = "\t"
    if (action == "normalize" || action == "raw") {
        for (repository_i = 1; repository_i <= repository_total;
             repository_i++)
            print repository_kinds[repository_i],
                  repository_names[repository_i],
                  repository_sources[repository_i],
                  repository_checkouts[repository_i],
                  repository_priorities[repository_i], repository_i
    } else if (action == "list" || action == "") {
        for (repository_i = 1; repository_i <= repository_total;
             repository_i++) {
            repository_kind = repository_kinds[repository_i]
            printf "%s\t%s\tpriority %s\t%s",
                   repository_names[repository_i], repository_kind,
                   repository_priorities[repository_i],
                   repository_sources[repository_i]
            if (repository_kind == "git")
                printf "\tcheckout %s", repository_checkouts[repository_i]
            printf "\n"
        }
    } else if (action == "status" || action == "status_raw") {
        repository_index_state = "missing"
        if (index_file != "") {
            while ((repository_getline = \
                    (getline repository_index_line < index_file)) > 0) {
                repository_index_fields_count = split(repository_index_line,
                                                      repository_index_fields,
                                                      "\t")
                if (repository_index_fields_count == 12 ||
                    repository_index_fields_count == 13)
                    repository_package_count[repository_index_fields[8]]++
            }
            if (repository_getline == 0)
                repository_index_state = "present"
            close(index_file)
        }

        for (repository_i = 1; repository_i <= repository_total;
             repository_i++) {
            repository_name = repository_names[repository_i]
            if (action == "status_raw")
                print repository_kinds[repository_i], repository_name,
                      repository_sources[repository_i],
                      repository_checkouts[repository_i],
                      repository_priorities[repository_i], repository_i,
                      (repository_index_state == "present" \
                       ? repository_package_count[repository_name] + 0 \
                       : "not-indexed")
            else if (repository_index_state == "present")
                printf "%s: %d packages (%s, priority %s, %s)\n",
                       repository_name,
                       repository_package_count[repository_name] + 0,
                       repository_kinds[repository_i],
                       repository_priorities[repository_i],
                       repository_checkouts[repository_i]
            else
                printf "%s: not indexed (%s, priority %s, %s)\n",
                       repository_name, repository_kinds[repository_i],
                       repository_priorities[repository_i],
                       repository_checkouts[repository_i]
        }
    } else {
        repository_error("unknown repository action '" action "'")
        exit 2
    }
}
