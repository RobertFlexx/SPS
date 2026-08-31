# Parse one or more recipes into repository index records. Build command
# fields are recognized here, but never executed. src update feeds a whole
# repository in one invocation; src check and the test parser still pass a
# single file.

function recipe_trim(value) {
    sub(/^[ \t]+/, "", value)
    sub(/[ \t]+$/, "", value)
    return value
}

function recipe_stderr(message,    command) {
    command = "cat >&2"
    print message | command
    close(command)
}

function recipe_error(message) {
    recipe_where = FILENAME
    recipe_at = FNR
    if (recipe_file != "")
        recipe_where = recipe_file
    if (recipe_emitting)
        recipe_at = recipe_last_fnr
    recipe_stderr("recipe: " recipe_where ":" recipe_at ": " message)
    recipe_failed = 1
}

function recipe_set_once(key, value) {
    if (recipe_seen[key]) {
        recipe_error("duplicate '" key "' field")
        return
    }
    recipe_seen[key] = 1
    recipe_value[key] = value
}

function recipe_append_dependency(key, value,    count, fields, i, item) {
    value = recipe_trim(value)
    gsub(/[ \t,]+/, " ", value)
    count = split(value, fields, /[ ]+/)
    for (i = 1; i <= count; i++) {
        item = recipe_trim(fields[i])
        if (item == "")
            continue
        if (recipe_value[key] != "")
            recipe_value[key] = recipe_value[key] ","
        recipe_value[key] = recipe_value[key] item
    }
}

function recipe_replace_all(value, needle, replacement,    result, position) {
    result = ""
    while ((position = index(value, needle)) != 0) {
        result = result substr(value, 1, position - 1) replacement
        value = substr(value, position + length(needle))
    }
    return result value
}

function recipe_expand(value,    pass, previous) {
    for (pass = 1; pass <= 8; pass++) {
        previous = value
        value = recipe_replace_all(value, "${name}", recipe_value["name"])
        value = recipe_replace_all(value, "${version}", recipe_value["version"])
        value = recipe_replace_all(value, "${release}", recipe_value["release"])
        value = recipe_replace_all(value, "${arch}", recipe_value["arch"])
        if (value == previous)
            break
    }
    return value
}

function recipe_safe_field(label, value) {
    if (value ~ /[[:cntrl:]]/) {
        recipe_error("'" label "' contains a control character")
        return 0
    }
    return 1
}

function recipe_valid_dependency_list(label, value,    count, items, i, item,
                                      position, name, wanted) {
    if (value == "")
        return 1
    count = split(value, items, ",")
    for (i = 1; i <= count; i++) {
        item = items[i]
        position = match(item, />=|<=|=|>|</)
        if (position) {
            name = substr(item, 1, RSTART - 1)
            wanted = substr(item, RSTART + RLENGTH)
        } else {
            name = item
            wanted = ""
        }
        if (name !~ /^[A-Za-z0-9][A-Za-z0-9+_.-]*$/ ||
            (position && wanted !~ /^[A-Za-z0-9][A-Za-z0-9._+~-]*$/)) {
            recipe_error("invalid " label " entry '" item "'")
            return 0
        }
    }
    return 1
}

function recipe_reset() {
    delete recipe_seen
    delete recipe_value
    delete recipe_hash
    recipe_source_count = 0
    recipe_hash_count = 0
    recipe_install_count = 0
    recipe_continuing = 0
    recipe_logical = ""
    recipe_failed = 0
    recipe_emitting = 0
}

function recipe_finish() {
    recipe_emitting = 1
    if (recipe_continuing)
        recipe_error("unterminated line continuation")

    if (!recipe_seen["name"])
        recipe_error("missing required 'name' field")
    if (!recipe_seen["version"])
        recipe_error("missing required 'version' field")
    if (!recipe_seen["release"])
        recipe_error("missing required 'release' field")
    if (!recipe_install_count)
        recipe_error("missing required 'install' command")
    if (recipe_source_count != recipe_hash_count)
        recipe_error("each source must have one corresponding hash")
    if (!recipe_seen["arch"]) {
        if (recipe_default_arch == "") {
            "uname -m" | getline recipe_default_arch
            close("uname -m")
        }
        recipe_value["arch"] = recipe_default_arch
    }

    recipe_value["name"] = recipe_expand(recipe_value["name"])
    recipe_value["version"] = recipe_expand(recipe_value["version"])
    recipe_value["release"] = recipe_expand(recipe_value["release"])
    recipe_value["arch"] = recipe_expand(recipe_value["arch"])
    recipe_value["description"] = recipe_expand(recipe_value["description"])
    recipe_value["depend"] = recipe_expand(recipe_value["depend"])
    recipe_value["builddep"] = recipe_expand(recipe_value["builddep"])
    recipe_value["optional"] = recipe_expand(recipe_value["optional"])
    recipe_value["conflict"] = recipe_expand(recipe_value["conflict"])

    for (recipe_i = 1; recipe_i <= recipe_hash_count; recipe_i++) {
        recipe_hash_value = recipe_expand(recipe_hash[recipe_i])
        recipe_hash_hex = substr(recipe_hash_value, 8)
        if (substr(recipe_hash_value, 1, 7) != "sha256:" ||
            length(recipe_hash_hex) != 64 ||
            recipe_hash_hex !~ /^[0123456789abcdefABCDEF]+$/)
            recipe_error("invalid source hash '" recipe_hash_value \
                         "' (expected sha256:<64 hex digits>)")
    }

    if (recipe_value["name"] !~ /^[A-Za-z0-9][A-Za-z0-9+_.-]*$/)
        recipe_error("invalid package name '" recipe_value["name"] "'")
    if (recipe_value["version"] !~ \
        /^[A-Za-z0-9][A-Za-z0-9._+~-]*$/)
        recipe_error("invalid version '" recipe_value["version"] "'")
    if (recipe_value["release"] !~ \
        /^[A-Za-z0-9][A-Za-z0-9._+~-]*$/)
        recipe_error("invalid release '" recipe_value["release"] "'")
    if (recipe_value["arch"] !~ /^[A-Za-z0-9][A-Za-z0-9._+-]*$/)
        recipe_error("invalid architecture '" recipe_value["arch"] "'")

    recipe_safe_field("name", recipe_value["name"])
    recipe_safe_field("version", recipe_value["version"])
    recipe_safe_field("release", recipe_value["release"])
    recipe_safe_field("arch", recipe_value["arch"])
    recipe_safe_field("description", recipe_value["description"])
    recipe_safe_field("repository", recipe_repo)
    recipe_safe_field("recipe path", recipe_path)
    recipe_valid_dependency_list("dependency", recipe_value["depend"])
    recipe_valid_dependency_list("build dependency", recipe_value["builddep"])
    recipe_valid_dependency_list("optional dependency", recipe_value["optional"])
    recipe_valid_dependency_list("conflict", recipe_value["conflict"])

    if (recipe_repo !~ /^[[:alnum:]][[:alnum:].+_-]*$/)
        recipe_error("invalid repository name '" recipe_repo "'")
    if (recipe_priority !~ /^-?[[:digit:]]+$/)
        recipe_error("invalid repository priority '" recipe_priority "'")
    if (recipe_path == "")
        recipe_error("recipe path is empty")
    if (length(recipe_sha256) != 64 || recipe_sha256 !~ /^[[:xdigit:]]+$/)
        recipe_error("invalid recipe SHA-256")

    recipe_emitting = 0
    if (recipe_failed) {
        recipe_any_failed = 1
        return
    }

    OFS = "\t"
    print recipe_value["name"], recipe_value["version"],
          recipe_value["release"], recipe_value["arch"],
          recipe_value["depend"], recipe_value["builddep"],
          recipe_value["optional"], recipe_repo, recipe_priority,
          recipe_path, recipe_value["description"], tolower(recipe_sha256),
          recipe_value["conflict"]
}

function recipe_process(line,    key, value, separator) {
    line = recipe_trim(line)
    if (line == "" || line ~ /^#/)
        return

    separator = match(line, /[ \t]/)
    if (!separator) {
        recipe_error("expected 'key value' record")
        return
    }
    key = substr(line, 1, RSTART - 1)
    value = recipe_trim(substr(line, RSTART + RLENGTH))
    if (value == "") {
        recipe_error("empty value for '" key "'")
        return
    }

    if (key == "name" || key == "version" || key == "release" ||
        key == "arch" || key == "description") {
        recipe_set_once(key, value)
    } else if (key == "depend" || key == "builddep" || key == "optional" ||
               key == "conflict") {
        recipe_append_dependency(key, value)
    } else if (key == "source") {
        recipe_source_count++
    } else if (key == "hash") {
        recipe_hash_count++
        recipe_hash[recipe_hash_count] = value
    } else if (key == "install") {
        recipe_install_count++
    } else if (key == "prepare" || key == "configure" || key == "build") {
        # mkpkg executes phase records later; indexing only validates their syntax.
    } else {
        recipe_error("unknown field '" key "'")
    }
}

BEGIN {
    if (recipe_digest_map != "") {
        while ((getline recipe_dline < recipe_digest_map) > 0) {
            recipe_n = split(recipe_dline, recipe_df, "\t")
            if (recipe_n >= 2)
                recipe_digest[recipe_df[1]] = recipe_df[2]
        }
        close(recipe_digest_map)
    }
    if (recipe_file_list != "") {
        while ((getline recipe_listed < recipe_file_list) > 0) {
            if (recipe_listed == "")
                continue
            ARGV[ARGC++] = recipe_listed
        }
        close(recipe_file_list)
        if (ARGC == 1) {
            recipe_skip_end = 1
            exit 0
        }
    }
}

FNR == 1 {
    if (recipe_active) {
        recipe_finish()
        if (recipe_any_failed)
            exit 2
    }
    recipe_reset()
    recipe_file = FILENAME
    recipe_last_fnr = FNR
    if (recipe_digest_map != "") {
        recipe_path = FILENAME
        recipe_sha256 = recipe_digest[FILENAME]
    }
    recipe_active = 1
}

{
    recipe_last_fnr = FNR
    recipe_line = $0
    sub(/\r$/, "", recipe_line)
    if (recipe_continuing)
        recipe_logical = recipe_logical recipe_line
    else
        recipe_logical = recipe_line

    if (recipe_logical ~ /\\[ \t]*$/) {
        sub(/\\[ \t]*$/, "", recipe_logical)
        recipe_logical = recipe_logical " "
        recipe_continuing = 1
        next
    }

    recipe_continuing = 0
    recipe_process(recipe_logical)
    recipe_logical = ""
}

END {
    if (recipe_skip_end)
        exit 0
    if (!recipe_any_failed && recipe_active)
        recipe_finish()
    if (recipe_any_failed)
        exit 2
}
