// There is only two type, tag or text.
Token_Type :: enum {
    TAG;
    TEXT;
}

Token :: struct {
    type: Token_Type;
    raw_string: string;
}

tokenize :: (s: string) -> []Token {
    pos := 0;

    tokens: [..]Token;
    while pos < s.count {
        new_pos := skip_whitespace(s, pos);

        if new_pos >= s.count {
            break;
        }

        token: Token;

        if s[new_pos] == #char "<" {
            end_pos := find_index_from_left(s, #char ">", new_pos);
            if end_pos < 0 {
                log_error("Unable to find closing angle bracket");
                break;
            }

            end_pos += 1;
            token.type = .TAG;
            token.raw_string = slice(s, new_pos, end_pos - new_pos);

            array_add(*tokens, token);
            pos = end_pos;
        } else {
            end_pos := find_index_from_left(s, #char "<", new_pos);
            if end_pos < 0 {
                break;
            }

            token.type = .TEXT;
            token.raw_string = slice(s, pos, end_pos - pos - 1);

            array_add(*tokens, token);
            pos = end_pos;
        }
    }

    return tokens;
}

skip_whitespace :: (s: string, pos: s64 = 0) -> s64 {
    new_pos := pos;
    while new_pos < s.count && is_space(s[new_pos]) {
        new_pos += 1;
    }

    return new_pos;
}

Tag_Type :: enum {
    UNDEFINED;
    DECLARATION;
    OPEN;
    CLOSE;
    SELF_CLOSE;
    COMMENT;
}

Attribute :: struct {
    key:   string;
    value: string;
}

Tag :: struct {
    type: Tag_Type;
    name: string;
    attrs: []Attribute;
}

parse_tag :: (token: Token) -> Tag {
    tag: Tag;
    if token.raw_string[1] == #char "?" {
        tag.type = .DECLARATION;
        found, left := split_from_left(slice(token.raw_string, 2, token.raw_string.count - 4), #char " ");
        if found {
            tag.name = left;
        }
    } else if token.raw_string[1] == #char "!" {
        // This should be a comment
        tag.type = .COMMENT;
    } else if token.raw_string[1] == #char "/" {
        tag.type = .CLOSE;
        // A close tag should almost always contain its tag name only
        tag.name = slice(token.raw_string, 2, token.raw_string.count - 3);
    } else if token.raw_string[token.raw_string.count - 2] == #char "/" {
        tag.type = .SELF_CLOSE;
        first_space := find_index_from_left(token.raw_string, #char " ");
        if first_space < 0 {
            // It is weird to have a self close tag which contains no attrs
            tag.name = slice(token.raw_string, 1, token.raw_string.count - 3);
        } else {
            tag.name = slice(token.raw_string, 1, first_space - 1);
            // Anything beyond the first space should be an attr pair
            tag.attrs = parse_attrs(slice(token.raw_string, first_space + 1, token.raw_string.count - first_space - 2));
        }
    } else {
        tag.type = .OPEN;
        first_space := find_index_from_left(token.raw_string, #char " ");
        if first_space < 0 {
            tag.name = slice(token.raw_string, 1, token.raw_string.count - 2);
        } else {
            tag.name = slice(token.raw_string, 1, first_space - 1);
            tag.attrs = parse_attrs(slice(token.raw_string, first_space + 1, token.raw_string.count - first_space - 1));
        }
    }

    assert(tag.type != .UNDEFINED);

    return tag;
}

parse_attrs :: (s: string) -> []Attribute {
    attrs: [..]Attribute;

    new_pos := skip_whitespace(s);

    while new_pos < s.count {
        equal_pos := find_index_from_left(s, #char "=", new_pos);
        if equal_pos < 0 {
            break;
        }

        attr: Attribute;
        attr.key = slice(s, new_pos, equal_pos - new_pos);
        first_quote_pos := find_index_from_left(s, #char "\"", new_pos);
        assert(first_quote_pos >= 0, "cannot find first quote pos in '%'", s);

        second_quote_pos := find_index_from_left(s, #char "\"", first_quote_pos + 1);
        assert(second_quote_pos >= 0, "cannot find second quote pos in '%'", s);

        attr.value = slice(s, first_quote_pos + 1, second_quote_pos - first_quote_pos - 1);
        array_add(*attrs, attr);
        new_pos = second_quote_pos + 2;
    }

    return attrs;
}

#import "Basic";
#import "String";
