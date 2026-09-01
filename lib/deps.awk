# Dependency graph handling for selected repository records. Load version.awk
# first when constraints need version comparison.

function deps_trim(value) {
    sub(/^[ \t]+/, "", value)
    sub(/[ \t]+$/, "", value)
    return value
}

function deps_stderr(message,    command) {
    command = "cat >&2"
    print message | command
    close(command)
}

function deps_error(message) {
    deps_stderr((program == "" ? "sget" : program) ": " message)
    deps_failed = 1
}

function deps_sort_names(values, count,    gap, i, j, saved) {
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

function deps_dependency_name(specification, parent,    position, operator,
                              name, wanted) {
    specification = deps_trim(specification)
    position = match(specification, />=|<=|=|>|</)
    if (position) {
        operator = substr(specification, RSTART, RLENGTH)
        name = substr(specification, 1, RSTART - 1)
        wanted = substr(specification, RSTART + RLENGTH)
    } else {
        operator = ""
        name = specification
        wanted = ""
    }

    if (name !~ /^[A-Za-z0-9][A-Za-z0-9+_.-]*$/ ||
        (operator != "" &&
         wanted !~ /^[A-Za-z0-9][A-Za-z0-9._+~-]*$/)) {
        deps_error("invalid dependency '" specification "' required by '" \
                   parent "'")
        return ""
    }
    if (!(name in deps_selected_priority)) {
        deps_error("dependency '" specification "' required by '" parent \
                   "' is unavailable")
        return ""
    }
    if (operator != "" &&
        !version_satisfies(deps_version[name], operator, wanted)) {
        deps_error("dependency '" specification "' required by '" parent \
                   "' is unavailable (selected " name "-" deps_version[name] \
                   ")")
        return ""
    }
    return name
}

function deps_list(package, include_package_build) {
    deps_combined = deps_runtime[package]
    if (include_package_build && deps_build[package] != "") {
        if (deps_combined != "")
            deps_combined = deps_combined ","
        deps_combined = deps_combined deps_build[package]
    }
    return deps_combined
}

function deps_cycle(package,    first, i, message) {
    first = 1
    for (i = 1; i <= deps_stack_depth; i++)
        if (deps_stack[i] == package) {
            first = i
            break
        }
    message = ""
    for (i = first; i <= deps_stack_depth; i++)
        message = message (message == "" ? "" : " -> ") deps_stack[i]
    message = message " -> " package
    deps_error("dependency cycle: " message)
}

function deps_visit(package, parent,    list, count, items, i, child) {
    if (!(package in deps_selected_priority)) {
        if (parent == "")
            deps_error("package '" package "' not found")
        else
            deps_error("dependency '" package "' required by '" parent \
                       "' is unavailable")
        return
    }
    if (deps_state[package] == 1) {
        deps_cycle(package)
        return
    }
    if (deps_state[package] == 2)
        return

    deps_state[package] = 1
    deps_stack_depth++
    deps_stack[deps_stack_depth] = package

    list = deps_list(package, include_build + 0)
    if (list != "") {
        count = split(list, items, ",")
        for (i = 1; i <= count; i++) {
            child = deps_dependency_name(items[i], package)
            if (child == "")
                continue
            deps_visit(child, package)
        }
    }

    delete deps_stack[deps_stack_depth]
    deps_stack_depth--
    deps_state[package] = 2
    if (!deps_failed) {
        deps_order_count++
        deps_order[deps_order_count] = package
    }
}

function deps_tree(package, prefix,    list, count, items, i, child) {
    if (deps_tree_seen[package]) {
        print prefix package " (already shown)"
        return
    }
    print prefix package
    deps_tree_seen[package] = 1

    list = deps_list(package, include_build + 0)
    if (list == "")
        return
    count = split(list, items, ",")
    for (i = 1; i <= count; i++) {
        child = deps_dependency_name(items[i], package)
        if (child != "")
            deps_tree(child, prefix "  ")
    }
}

BEGIN {
    FS = OFS = "\t"
}

/^$/ {
    next
}

{
    if (NF != 12 && NF != 13) {
        deps_error(FILENAME ":" FNR \
                   ": malformed index record (expected 12 or 13 fields)")
        next
    }
    if ($1 !~ /^[A-Za-z0-9][A-Za-z0-9+_.-]*$/ ||
        $2 !~ /^[A-Za-z0-9][A-Za-z0-9._+~-]*$/ ||
        $9 !~ /^-?[[:digit:]]+$/ || $10 == "" ||
        length($12) != 64 || $12 !~ /^[[:xdigit:]]+$/) {
        deps_error(FILENAME ":" FNR ": invalid index record for '" $1 "'")
        next
    }

    if (!($1 in deps_selected_priority)) {
        deps_name_count++
        deps_names[deps_name_count] = $1
        deps_selected_priority[$1] = $9 + 0
        deps_version[$1] = $2
        deps_release[$1] = $3
        deps_arch[$1] = $4
        deps_runtime[$1] = $5
        deps_build[$1] = $6
        deps_recipe[$1] = $10
        deps_recipe_sha256[$1] = $12
        deps_conflict[$1] = (NF >= 13 ? $13 : "")
    } else if (($9 + 0) > deps_selected_priority[$1]) {
        deps_selected_priority[$1] = $9 + 0
        deps_version[$1] = $2
        deps_release[$1] = $3
        deps_arch[$1] = $4
        deps_runtime[$1] = $5
        deps_build[$1] = $6
        deps_recipe[$1] = $10
        deps_recipe_sha256[$1] = $12
        deps_conflict[$1] = (NF >= 13 ? $13 : "")
    }
}

END {
    if (deps_failed)
        exit 5
    if (action == "validate") {
        deps_sort_names(deps_names, deps_name_count)
        for (deps_i = 1; deps_i <= deps_name_count; deps_i++)
            deps_visit(deps_names[deps_i], "")
        if (deps_failed)
            exit 5
        exit 0
    }
    if (roots == "") {
        deps_error("no package specified")
        exit 2
    }

    deps_root_count = split(roots, deps_roots, ",")
    for (deps_i = 1; deps_i <= deps_root_count; deps_i++) {
        if (deps_roots[deps_i] !~ \
            /^[A-Za-z0-9][A-Za-z0-9+_.-]*$/) {
            deps_error("invalid package name '" deps_roots[deps_i] "'")
            continue
        }
        deps_visit(deps_roots[deps_i], "")
    }
    if (deps_failed)
        exit 5

    # installed=name,name from sget: already-installed packages.
    if (installed != "") {
        deps_ninst = split(installed, deps_inst, ",")
        for (deps_i = 1; deps_i <= deps_ninst; deps_i++) {
            if (deps_inst[deps_i] != "")
                deps_installed[deps_inst[deps_i]] = 1
        }
    }
    for (deps_i = 1; deps_i <= deps_order_count; deps_i++)
        deps_in_order[deps_order[deps_i]] = 1
    for (deps_i = 1; deps_i <= deps_order_count; deps_i++) {
        deps_package = deps_order[deps_i]
        if (deps_conflict[deps_package] == "")
            continue
        deps_nc = split(deps_conflict[deps_package], deps_citems, ",")
        for (deps_j = 1; deps_j <= deps_nc; deps_j++) {
            deps_other = deps_citems[deps_j]
            if (deps_other == "" || deps_other == deps_package)
                continue
            if (deps_in_order[deps_other]) {
                deps_error("package '" deps_package "' conflicts with '" \
                           deps_other "' (both in this transaction)")
                break
            }
            if (deps_installed[deps_other]) {
                deps_error("package '" deps_package "' conflicts with installed '" \
                           deps_other "'")
                break
            }
        }
        if (deps_failed)
            break
    }
    if (deps_failed)
        exit 5

    if (action == "order" || action == "plan") {
        for (deps_i = 1; deps_i <= deps_order_count; deps_i++) {
            deps_package = deps_order[deps_i]
            if (action == "plan")
                print deps_package, deps_recipe[deps_package],
                      deps_recipe_sha256[deps_package], deps_version[deps_package],
                      deps_release[deps_package], deps_arch[deps_package]
            else
                print deps_package
        }
    } else if (action == "tree") {
        for (deps_i = 1; deps_i <= deps_root_count; deps_i++)
            deps_tree(deps_roots[deps_i], "")
    } else {
        deps_stderr((program == "" ? "sget" : program) \
                    ": unknown dependency action '" action "'")
        exit 2
    }
    if (deps_failed)
        exit 5
}
