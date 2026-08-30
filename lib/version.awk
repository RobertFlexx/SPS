# POSIX AWK version comparison. Versions are split into numeric and alphabetic
# runs; punctuation separates runs, leading zeroes do not change numeric order,
# and `~` sorts before other tokens. This is SPS's own small comparison rule.

function version_tokenize(version, values, types,    count, i, c, start) {
    for (i in values)
        delete values[i]
    for (i in types)
        delete types[i]

    count = 0
    i = 1
    while (i <= length(version)) {
        c = substr(version, i, 1)
        if (c == "~") {
            count++
            values[count] = c
            types[count] = "tilde"
            i++
        } else if (c ~ /[[:digit:]]/) {
            start = i
            while (i <= length(version) &&
                   substr(version, i, 1) ~ /[[:digit:]]/)
                i++
            count++
            values[count] = substr(version, start, i - start)
            types[count] = "number"
        } else if (c ~ /[[:alpha:]]/) {
            start = i
            while (i <= length(version) &&
                   substr(version, i, 1) ~ /[[:alpha:]]/)
                i++
            count++
            values[count] = tolower(substr(version, start, i - start))
            types[count] = "text"
        } else {
            i++
        }
    }
    return count
}

function version_compare_number(left, right,    a, b) {
    a = left
    b = right
    sub(/^0+/, "", a)
    sub(/^0+/, "", b)
    if (a == "")
        a = "0"
    if (b == "")
        b = "0"

    if (length(a) < length(b))
        return -1
    if (length(a) > length(b))
        return 1
    if ("x" a < "x" b)
        return -1
    if ("x" a > "x" b)
        return 1
    return 0
}

function version_remaining_sign(values, types, first, count,    i, value) {
    for (i = first; i <= count; i++) {
        if (types[i] == "tilde")
            return -1
        if (types[i] == "number") {
            value = values[i]
            sub(/^0+/, "", value)
            if (value != "")
                return 1
        } else {
            return 1
        }
    }
    return 0
}

function version_compare(left, right,    left_count, right_count, count,
                         i, left_type, right_type, result) {
    left_count = version_tokenize(left, version_left_values,
                                  version_left_types)
    right_count = version_tokenize(right, version_right_values,
                                   version_right_types)
    count = left_count < right_count ? left_count : right_count

    for (i = 1; i <= count; i++) {
        left_type = version_left_types[i]
        right_type = version_right_types[i]

        if (left_type == "tilde" || right_type == "tilde") {
            if (left_type != right_type)
                return left_type == "tilde" ? -1 : 1
            continue
        }

        if (left_type != right_type)
            return left_type == "number" ? 1 : -1

        if (left_type == "number")
            result = version_compare_number(version_left_values[i],
                                            version_right_values[i])
        else if (version_left_values[i] < version_right_values[i])
            result = -1
        else if (version_left_values[i] > version_right_values[i])
            result = 1
        else
            result = 0

        if (result != 0)
            return result
    }

    if (left_count > count)
        return version_remaining_sign(version_left_values,
                                      version_left_types,
                                      count + 1, left_count)
    if (right_count > count)
        return -version_remaining_sign(version_right_values,
                                       version_right_types,
                                       count + 1, right_count)
    return 0
}

function version_satisfies(have, operator, wanted,    comparison) {
    comparison = version_compare(have, wanted)
    if (operator == "=")
        return comparison == 0
    if (operator == ">")
        return comparison > 0
    if (operator == ">=")
        return comparison >= 0
    if (operator == "<")
        return comparison < 0
    if (operator == "<=")
        return comparison <= 0
    return 0
}

END {
    if (version_action == "compare")
        print version_compare(version_a, version_b)
    else if (version_action == "satisfies")
        print version_satisfies(version_a, version_operator, version_b) ? 1 : 0
}
