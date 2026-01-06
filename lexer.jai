Token_Type :: enum u8 {
    ERROR;
    TAG;
    INNER;
    EOF;
}

Token :: struct {
    type: Token_Type;
    l0, c0: s32;
    l1, c1: s32 = -1;

    raw: string;

    union {
        tag: Tag;
        str: string;
    }
}

Tag_Type :: enum u8 {
    DECLARATION;
    OPEN;
    CLOSE;
    SELF_CLOSE;
    COMMENT;
}

Tag_Attribute :: struct {
    key: string;
    value: string;
}

Tag :: struct {
    type: Tag_Type;
    name: string;
    attrs: [..]Tag_Attribute;
}

Lexer :: struct {
    current_line_number: s32;
    current_character_index: s32;

    input: string;
    input_cursor: s64;

    reported_error := false;
}

peek_next_character :: (using lexer: *Lexer) -> s16 {
    if input_cursor >= input.count {
        return -1;
    }

    return input[input_cursor];
}

eat_character :: (using lexer: *Lexer) {
    if input[input_cursor] == #char "\n" {
        current_line_number += 1;
        current_character_index = 0;
    }

    input_cursor += 1;
    current_character_index += 1;
}

report_parse_error :: (lexer: *Lexer, format: string, arguments: .. Any) {
    log(format, .. arguments);
    log("... at line %, character %.\n", lexer.current_line_number, lexer.current_character_index);
    lexer.reported_error = true;
} @PrintLike

report_parse_error :: (lexer: *Lexer, token: *Token, format: string, arguments: .. Any) {
    log(format, .. arguments);
    log("... at line %, character %.\n", token.l0, token.c0);
    lexer.reported_error = true;
} @PrintLike

get_token :: (lexer: *Lexer) -> Token {
    token: Token;
    while 1 {
        c := peek_next_character(lexer);
        if c < 0 return .{ type = .EOF };

        if c == #char "<" {
            token = make_tag(lexer);
            break;
        } else {
            token = make_inner_string(lexer);
            break;
        }
    }

    if token.type == .INNER {
        is_all_space := true;
        for token.raw {
            if !is_space(it) {
                is_all_space = false;
            }
        }
        if is_all_space {
            return get_token(lexer);
        }
    }

    return token;
}

skip_spaces :: (lexer: *Lexer) {
    while 1 {
        c := peek_next_character(lexer);
        if c < 0 break;

        if is_space(xx c) {
            eat_character(lexer);
        } else {
            return;
        }
    }
}

make_empty_token :: (using lexer: *Lexer) -> Token {
    t := Token.{
        l0 = current_line_number,
        c0 = current_character_index,
    };

    t.raw.data = input.data + input_cursor;

    return t;
}

set_end_of_token :: (using lexer: *Lexer, token: *Token) {
    token.l1 = lexer.current_line_number;
    token.c1 = lexer.current_character_index;
    token.raw.count = input.data + input_cursor - token.raw.data;
}

make_tag :: (using lexer: *Lexer) -> Token {
    t := make_empty_token(lexer);
    t.type = .TAG;

    start := input_cursor;

    // When calling this function, the first char is checked to be '<'
    eat_character(lexer);

    State :: enum u8 {
        UNINIT;
        NAME;
        ATTR;
        SKIP;
    }

    state : State = .UNINIT;
    while 1 {
        c := peek_next_character(lexer);
        if c < 0 break;

        skip_spaces(lexer);

        if c == #char ">" {
            state = .UNINIT;
            eat_character(lexer);
            break;
        } else if state == {
        case .UNINIT;
            if c == {
            case #char "!";
                // bang is not a declaration in xml
                //
                // If you want to support html in this package, it
                // would be a hard time.
                t.tag.type = .COMMENT;
                state = .SKIP;
                eat_character(lexer);
            case #char "?";
                t.tag.type = .DECLARATION;
                state = .SKIP;
                eat_character(lexer);
            case #char "/";
                t.tag.type = .CLOSE;
                state = .NAME;
                eat_character(lexer);
            case;
                t.tag.type = .OPEN;
                state = .NAME;
            }

        case .NAME;
            name := parse_identifier(lexer);
            t.tag.name = copy_string(name);

            if t.tag.type == .CLOSE {
                state = .SKIP;
            } else {
                state = .ATTR;
            }

        case .ATTR;
            if c == #char "/" {
                eat_character(lexer);
                t.tag.type = .SELF_CLOSE;
                state = .SKIP;
                continue;
            }

            // We assume there is no space around the equal sign in
            // attributes.
            //
            // GOOD: key="value"
            // BAD:  key = "value"
            attr: Tag_Attribute;
            key := parse_identifier(lexer);
            attr.key = copy_string(key);

            char := peek_next_character(lexer);
            if char < 0 {
                report_parse_error(lexer, "Find EOF in the middle of attr");
                t.type = .ERROR;
                return t;
            }

            if char == #char "=" {
                eat_character(lexer);

                s := parse_string(lexer);
                value, ok := unescape(s);
                if !ok {
                    report_parse_error(lexer, "unescape goes wrong");
                    t.type = .ERROR;
                    return t;
                }
                attr.value = value;
            }

            array_add(*t.tag.attrs, attr);

        case .SKIP;
            eat_character(lexer);
        }
    }

    t.raw = slice(input, start, input_cursor - start);

    set_end_of_token(lexer, *t);
    return t;
}

make_inner_string :: (using lexer: *Lexer) -> Token {
    t := make_empty_token(lexer);
    t.type = .INNER;

    start := lexer.input_cursor;
    while 1 {
        c := peek_next_character(lexer);
        if c < 0 break;

        if c == #char "<" {
            break;
        }
        eat_character(lexer);
    }

    t.raw = slice(input, start, input_cursor - start);
    t.str = copy_string(t.raw);

    set_end_of_token(lexer, *t);
    t.type == .INNER;

    assert(t.type != .ERROR);
    return t;
}

parse_identifier :: (using lexer: *Lexer) -> string {
    start := input_cursor;
    while 1 {
        char := peek_next_character(lexer);
        if char < 0 break;

        c := cast(u8)char;

        if is_space(c) || c == #char ">" || c == #char "/" || c == #char "=" {
            break;
        }
        eat_character(lexer);
    }

    s := slice(input, start, input_cursor - start);

    return s;
}

parse_string :: (using lexer: *Lexer) -> string {
    start := input_cursor;

    // Eat the first double quote
    eat_character(lexer);

    prev_char: u8 = 0;
    while 1 {
        c := peek_next_character(lexer);
        if c < 0 break;

        eat_character(lexer);
        if c == #char "\"" && prev_char != #char "\\" {
            break;
        }

        prev_char = xx c;
    }

    s := slice(input, start, input_cursor - start);
    s = unquote(s);

    return s;
}

unquote :: (s: string) -> string {
    if s.count > 0 {
        if s[0] == #char "\"" && s[s.count - 1] == #char "\"" {
            return slice(s, 1, s.count - 2);
        }
    }

    return s;
}

unescape :: (s: string) -> string, success:bool {
    sb: String_Builder;

    i := 0;
    while i < s.count {
        c := s[i];
        if c == #char "\\" {
            i += 1;
            if i < s.count {
                if s[i] == {
                case #char "\\";
                    append(*sb, #char "\\");
                case #char "\"";
                    append(*sb, #char "\"");
                case #char "/";
                    // This is an optional escape in json.
                    append(*sb, #char "/");
                // case #char "b";
                //     // Backspace, rarely use.
                //     append(*sb, #char "\b");
                // case #char "f";
                //     append(*sb, #char "\f");
                case #char "n";
                    append(*sb, #char "\n");
                case #char "r";
                    append(*sb, #char "\r");
                case #char "t";
                    append(*sb, #char "\t");
                case #char "u";
                    // Nightmare
                    // To parse this, we have to ensure the next 4 chars are hex.
                    if i + 4 >= s.count {
                        return "", false;
                    }
                    result, success := string_to_int(slice(s, i + 1, 4), 16, u32);
                    if !success {
                        return "", false;
                    }

                    stack_data: [4]u8;
                    stack_string := cast(string)stack_data;
                    character_utf32_to_utf8(result, *stack_string);
                    append(*sb, stack_string);
                }
            }
        } else {
            append(*sb, c);
        }

        i += 1;
    }

    str := builder_to_string(*sb);

    return str, true;
}

set_input_from_string :: (lexer: *Lexer, input: string) {
    lexer.input = input;
    lexer.input_cursor = 0;
    lexer.current_line_number = 1;
    lexer.current_character_index = 1;
}

set_input_from_file :: (lexer: *Lexer, file_path: string) -> bool {
    s, ok := read_entire_file(file_path);
    if !ok return false;

    set_input_from_string(lexer, s);

    return true;
}

#import "Basic";
#import "String";
#import "Unicode";
#import "File";
