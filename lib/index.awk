# Queries over the aggregate package index. For equal priorities, the first
# record wins; src writes records in config order and then recipe-path order.

function index_stderr(message,    command) {
    command = "cat >&2"
    print message | command
    close(command)
}

function index_error(message) {
    index_stderr((program == "" ? "src" : program) ": " message)
    index_failed = 1
}

function index_sort_names(values, count,    gap, i, j, saved) {
    gap = int(count / 2)
    while (gap > 0) {
        for (i = gap + 1; i <= count; i++) {
            saved = values[i]
            j = i
            while (j > gap && values[j - gap] > saved) {
                values[j] = values[j - gap]
                j -= gap
            }
            values[j] = saved
        }
        gap = int(gap / 2)
    }
}

function index_selected_fields(name) {
    return split(index_selected_line[name], index_output_fields, FS)
}

function index_print_show(name) {
    index_selected_fields(name)
    print "name: " index_output_fields[1]
    print "version: " index_output_fields[2]
    print "release: " index_output_fields[3]
    print "architecture: " index_output_fields[4]
    print "repository: " index_output_fields[8]
    print "priority: " index_output_fields[9]
    print "recipe: " index_output_fields[10]
    print "description: " index_output_fields[11]
    print "dependencies: " (index_output_fields[5] == "" \
                            ? "-" : index_output_fields[5])
    print "build dependencies: " (index_output_fields[6] == "" \
                                  ? "-" : index_output_fields[6])
    print "optional dependencies: " (index_output_fields[7] == "" \
                                     ? "-" : index_output_fields[7])
    print "recipe sha256: " index_output_fields[12]
}

BEGIN {
    FS = OFS = "\t"
}

/^$/ {
    next
}

{
    if (NF != 12) {
        index_error(FILENAME ":" FNR ": malformed index record (expected 12 fields)")
        next
    }
    if ($1 !~ /^[A-Za-z0-9][A-Za-z0-9+_.-]*$/ ||
        $2 !~ /^[A-Za-z0-9][A-Za-z0-9._+~-]*$/ ||
        $3 !~ /^[A-Za-z0-9][A-Za-z0-9._+~-]*$/ ||
        $4 !~ /^[A-Za-z0-9][A-Za-z0-9._+-]*$/ ||
        $8 !~ /^[[:alnum:]][[:alnum:].+_-]*$/ ||
        $9 !~ /^-?[[:digit:]]+$/ || $10 == "" ||
        length($12) != 64 || $12 !~ /^[[:xdigit:]]+$/) {
        index_error(FILENAME ":" FNR ": invalid index record for '" $1 "'")
        next
    }

    index_records++
    index_record_line[index_records] = $0
    index_record_name[index_records] = $1

    if (!($1 in index_selected_line)) {
        index_name_count++
        index_names[index_name_count] = $1
        index_selected_line[$1] = $0
        index_selected_priority[$1] = $9 + 0
        index_selected_record[$1] = index_records
    } else if (($9 + 0) > index_selected_priority[$1]) {
        index_selected_line[$1] = $0
        index_selected_priority[$1] = $9 + 0
        index_selected_record[$1] = index_records
    }
}

END {
    if (index_failed)
        exit 2

    index_sort_names(index_names, index_name_count)

    if (action == "validate") {
        exit 0
    } else if (action == "all" || action == "search" ||
               action == "search_raw") {
        index_needle = tolower(query)
        for (index_i = 1; index_i <= index_name_count; index_i++) {
            index_name = index_names[index_i]
            index_selected_fields(index_name)
            index_haystack = tolower(index_output_fields[1] "\t" \
                                     index_output_fields[11])
            if (action != "all" &&
                index(index_haystack, index_needle) == 0)
                continue
            if (action == "all" || action == "search_raw")
                print index_selected_line[index_name]
            else
                printf "%s\t%s-%s\t%s\t%s\n",
                       index_output_fields[1], index_output_fields[2],
                       index_output_fields[3], index_output_fields[8],
                       index_output_fields[11]
        }
    } else if (action == "show" || action == "exact" ||
               action == "field" || action == "install_record") {
        if (!(query in index_selected_line)) {
            index_stderr((program == "" ? "src" : program) \
                         ": package '" query "' not found")
            exit 3
        }
        if (action == "show")
            index_print_show(query)
        else if (action == "exact")
            print index_selected_line[query]
        else if (action == "install_record") {
            index_selected_fields(query)
            print index_output_fields[1], index_output_fields[10],
                  index_output_fields[12], index_output_fields[2],
                  index_output_fields[3], index_output_fields[4]
        } else {
            if (field !~ /^[[:digit:]]+$/ || field < 1 || field > 12) {
                index_stderr((program == "" ? "src" : program) \
                             ": invalid index field '" field "'")
                exit 2
            }
            index_selected_fields(query)
            print index_output_fields[field]
        }
    } else if (action == "which") {
        if (!(query in index_selected_line)) {
            index_stderr((program == "" ? "src" : program) \
                         ": package '" query "' not found")
            exit 3
        }

        index_selected_fields(query)
        print "selected: " index_output_fields[8] " " index_output_fields[10]
        print "version: " index_output_fields[2] "-" index_output_fields[3]
        print "priority: " index_output_fields[9]

        index_alternatives = 0
        for (index_i = 1; index_i <= index_records; index_i++)
            if (index_record_name[index_i] == query &&
                index_i != index_selected_record[query])
                index_alternatives++

        if (index_alternatives) {
            print ""
            print "also available:"
            for (index_i = 1; index_i <= index_records; index_i++) {
                if (index_record_name[index_i] != query ||
                    index_i == index_selected_record[query])
                    continue
                split(index_record_line[index_i], index_output_fields, FS)
                printf "%s %s %s-%s priority %s\n",
                       index_output_fields[8], index_output_fields[10],
                       index_output_fields[2], index_output_fields[3],
                       index_output_fields[9]
            }
        }
    } else {
        index_stderr((program == "" ? "src" : program) \
                     ": unknown index action '" action "'")
        exit 2
    }
}
