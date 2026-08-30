# Parse and print repository configuration. Input is: repo NAME PATH [PRIORITY]

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
    if (repository_count_fields < 3 || repository_count_fields > 4 ||
        repository_fields[1] != "repo") {
        repository_error(FILENAME ":" FNR \
                         ": expected 'repo NAME PATH [PRIORITY]'")
        next
    }

    repository_name = repository_fields[2]
    repository_path = repository_fields[3]
    repository_priority = repository_count_fields == 4 \
                          ? repository_fields[4] : 0

    if (repository_name !~ /^[[:alnum:]][[:alnum:].+_-]*$/) {
        repository_error(FILENAME ":" FNR ": invalid repository name '" \
                         repository_name "'")
        next
    }
    if (repository_path == "" || repository_path ~ /[[:cntrl:]]/) {
        repository_error(FILENAME ":" FNR ": invalid path for repository '" \
                         repository_name "'")
        next
    }
    if (repository_priority !~ /^-?[[:digit:]]+$/) {
        repository_error(FILENAME ":" FNR ": invalid priority '" \
                         repository_priority "'")
        next
    }
    if (repository_seen[repository_name]) {
        repository_error(FILENAME ":" FNR ": duplicate repository '" \
                         repository_name "'")
        next
    }

    repository_seen[repository_name] = 1
    repository_total++
    repository_names[repository_total] = repository_name
    repository_paths[repository_total] = repository_path
    repository_priorities[repository_total] = repository_priority
}

END {
    if (repository_failed)
        exit 2

    OFS = "\t"
    if (action == "normalize" || action == "raw") {
        for (repository_i = 1; repository_i <= repository_total;
             repository_i++)
            print repository_names[repository_i],
                  repository_paths[repository_i],
                  repository_priorities[repository_i], repository_i
    } else if (action == "list" || action == "") {
        for (repository_i = 1; repository_i <= repository_total;
             repository_i++)
            printf "%s\tpriority %s\t%s\n",
                   repository_names[repository_i],
                   repository_priorities[repository_i],
                   repository_paths[repository_i]
    } else if (action == "status" || action == "status_raw") {
        repository_index_state = "missing"
        if (index_file != "") {
            while ((repository_getline = \
                    (getline repository_index_line < index_file)) > 0) {
                repository_index_fields_count = split(repository_index_line,
                                                      repository_index_fields,
                                                      "\t")
                if (repository_index_fields_count == 12)
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
                print repository_name,
                      repository_priorities[repository_i],
                      repository_paths[repository_i],
                      (repository_index_state == "present" \
                       ? repository_package_count[repository_name] + 0 \
                       : "not-indexed")
            else if (repository_index_state == "present")
                printf "%s: %d packages (priority %s, %s)\n",
                       repository_name,
                       repository_package_count[repository_name] + 0,
                       repository_priorities[repository_i],
                       repository_paths[repository_i]
            else
                printf "%s: not indexed (priority %s, %s)\n",
                       repository_name,
                       repository_priorities[repository_i],
                       repository_paths[repository_i]
        }
    } else {
        repository_error("unknown repository action '" action "'")
        exit 2
    }
}
