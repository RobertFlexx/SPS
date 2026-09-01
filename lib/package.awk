# Package metadata validation. This module is run with -v sps_action=ACTION and
# returns non-zero for malformed input.

BEGIN {
    sps_errors = 0
    sps_stderr = "cat >&2"
    sps_tab = sprintf("%c", 9)
}

function sps_diag(message) {
    print (sps_program != "" ? sps_program ": " : "") message | sps_stderr
    sps_errors++
}

function sps_valid_name(value) {
    return value ~ /^[ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789][ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+_.-]*$/
}

function sps_valid_path(path, directories,    value, count, part, pieces, i) {
    value = path
    if (value == "" || value ~ /[[:cntrl:]]/ || value ~ /^\// ||
        value ~ /^\.\// || value ~ /\/\//)
        return 0

    if (directories && value ~ /\/$/)
        sub(/\/$/, "", value)
    if (value == "" || value ~ /\/$/)
        return 0

    count = split(value, pieces, "/")
    for (i = 1; i <= count; i++) {
        part = pieces[i]
        if (part == "" || part == "." || part == "..")
            return 0
    }
    return 1
}

function sps_meta_line(line,    pos, key, value, controls) {
    if (line ~ /^[[:space:]]*$/)
        return 1
    controls = line
    if (line ~ /^[[:space:]]/ || line ~ /[\r\n]/)
        return 0

    pos = match(line, /[[:space:]]/)
    if (!pos)
        return 0
    key = substr(line, 1, pos - 1)
    value = substr(line, pos)
    sub(/^[[:space:]]+/, "", value)
    sub(/[[:space:]]+$/, "", value)
    if (key !~ /^[abcdefghijklmnopqrstuvwxyz][abcdefghijklmnopqrstuvwxyz0123456789_-]*$/ ||
        value == "" || value ~ /[[:cntrl:]]/)
        return 0

    sps_meta_count[key]++
    if (!(key in sps_meta_first))
        sps_meta_first[key] = value
    if ((key == "format" || key == "definition_sha256" || key == "name" ||
         key == "version" || key == "release" || key == "arch") &&
        sps_meta_count[key] > 1) {
        sps_diag("duplicate metadata key '" key "'")
        return 1
    }
    if (key == "format" && value != "1")
        sps_diag("unsupported package format '" value "'")
    if (key == "definition_sha256" &&
        (value !~ /^[0123456789abcdef]+$/ || length(value) != 64))
        sps_diag("invalid package definition digest")
    if (key == "name" && !sps_valid_name(value))
        sps_diag("invalid package name '" value "'")
    if ((key == "version" || key == "release") &&
        value !~ /^[ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789][ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789._+~-]*$/)
        sps_diag("invalid " key " value '" value "'")
    if (key == "arch" &&
        value !~ /^[ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789][ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789._+-]*$/)
        sps_diag("invalid arch value '" value "'")
    return 1
}

sps_action == "validate-meta" || sps_action == "meta-get" || sps_action == "meta-id" {
    if (!sps_meta_line($0))
        sps_diag("malformed metadata at line " FNR)
    next
}

sps_action == "validate-paths" {
    if (!sps_valid_path($0, 1)) {
        sps_diag("unsafe manifest path at line " FNR ": " $0)
        next
    }
    sps_path = $0
    sub(/\/$/, "", sps_path)
    if (sps_path == ".SPS" || sps_path ~ /^\.SPS\//) {
        sps_diag("reserved manifest path at line " FNR ": " $0)
        next
    }
    if (sps_seen_path[sps_path]++)
        sps_diag("duplicate manifest path '" sps_path "'")
    next
}

sps_action == "validate-hashes" || sps_action == "hash-paths" {
    if (split($0, sps_hash_field, sps_tab) != 3 ||
        sps_hash_field[1] != "sha256" ||
        sps_hash_field[2] !~ /^[0123456789abcdef]+$/ ||
        length(sps_hash_field[2]) != 64 ||
        !sps_valid_path(sps_hash_field[3], 0)) {
        sps_diag("malformed hash record at line " FNR)
        next
    }
    if (sps_hash_seen[sps_hash_field[3]]++)
        sps_diag("duplicate hash path '" sps_hash_field[3] "'")
    if (sps_action == "hash-paths")
        print sps_hash_field[3]
    next
}

sps_action == "normalize-members" {
    sps_member = $0
    while (sps_member ~ /^\.\//)
        sub(/^\.\//, "", sps_member)
    if (sps_member == "" || sps_member == ".")
        next
    if (!sps_valid_path(sps_member, 1)) {
        sps_diag("unsafe archive member at line " FNR ": " $0)
        next
    }
    sps_member_key = sps_member
    sub(/\/$/, "", sps_member_key)
    if (sps_seen_member[sps_member_key]++) {
        sps_diag("duplicate archive member '" sps_member_key "'")
        next
    }
    if (sps_member_key ~ /^\.SPS\// &&
        sps_member_key != ".SPS/meta" &&
        sps_member_key != ".SPS/files" &&
        sps_member_key != ".SPS/hashes" &&
        sps_member_key != ".SPS/hooks" &&
        sps_member_key != ".SPS/hooks/pre-install" &&
        sps_member_key != ".SPS/hooks/post-install" &&
        sps_member_key != ".SPS/hooks/pre-remove" &&
        sps_member_key != ".SPS/hooks/post-remove") {
        sps_diag("unsupported package control member '" sps_member_key "'")
        next
    }
    print sps_member
    next
}

END {
    if (sps_action == "validate-meta" || sps_action == "meta-get" ||
        sps_action == "meta-id") {
        sps_required[1] = "format"
        sps_required[2] = "name"
        sps_required[3] = "version"
        sps_required[4] = "release"
        sps_required[5] = "arch"
        for (sps_i = 1; sps_i <= 5; sps_i++) {
            sps_key = sps_required[sps_i]
            if (sps_meta_count[sps_key] != 1)
                sps_diag("missing required metadata key '" sps_key "'")
        }
        if (!sps_errors && sps_action == "meta-get") {
            if (!(sps_key_name in sps_meta_first))
                sps_diag("metadata key '" sps_key_name "' is not present")
            else
                print sps_meta_first[sps_key_name]
        }
        if (!sps_errors && sps_action == "meta-id")
            print sps_meta_first["name"] "\t" sps_meta_first["version"] "\t" \
                  sps_meta_first["release"] "\t" sps_meta_first["arch"]
    }
    if (sps_action != "" && sps_action != "validate-meta" &&
        sps_action != "meta-get" && sps_action != "meta-id" &&
        sps_action != "validate-paths" && sps_action != "validate-hashes" &&
        sps_action != "hash-paths" && sps_action != "normalize-members")
        sps_diag("unknown package action '" sps_action "'")
    close(sps_stderr)
    if (sps_errors)
        exit 1
}
