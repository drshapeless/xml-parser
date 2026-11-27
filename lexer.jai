Token_Kind :: enum {
    UNKNOWN;
    EOF;

    OPEN_TAG_START;
    CLOSE_TAG_START;
    TAG_END;
    SELF_CLOSING_END;

    NAME;
    EQUALS;
    ATTRIBUTE_VALUE;

    TEXT;

    COMMENT;
    CDATA;

    PROCESSING_INSTRUCTION_START;
    PROCESSING_INSTRUCTION_END;

    DOCTYPE;
}

Token :: struct {
    kind:   Token_Kind;
    text:   string;

    line:   s32; // starts at 1
    column: s32; // starts at 1
    offset: s64;
}

Lexer_Mode :: enum {
    OUTSIDE;
    INSIDE_TAG;
    INSIDE_ATTRIBUTE_VALUE;
    INSIDE_DOCTYPE;
    INSIDE_DOCUMENT_TYPE_DEFINITION; // DTD
    INSIDE_CDATA;
    INSIDE_COMMENT;
}

Lexer :: struct {
    current_line:   s32 = 1;
    current_column: s32 = 1;
    current_offset: s64 = 0;

    document:  string;

    mode: Lexer_Mode = .OUTSIDE;
}

// If the offset exceed the document count.
peek_char :: (using lexer: *Lexer, offset: s64 = 0) -> bool, u8 #no_abc {
    i := current_offset + offset;

    if i >= document.count {
        return false, 0;
    }

    return true, document[i];
}

peek_string :: (using lexer: *Lexer, count: s64) -> bool, string {
    if current_offset + count >= document.count {
        return false, "";
    } else {
        return true, slice(document, current_offset, count);
    }
}

consume :: (using lexer: *Lexer, count: s64) {
    for 0..count-1 {
        ok, c := peek_char(lexer);
        if !ok {
            return;
        }

        if c == #char "\n" {
            current_line += 1;
            current_column = 1;
        } else {
            current_column += 1;
        }

        current_offset += 1;
    }
}

make_token :: (using lexer: *Lexer, kind: Token_Kind, length: s64) -> Token {
    return Token.{
        kind = kind,
        text = .{data = document.data + current_offset, count = length},
        line = current_line,
        column = current_column,
        offset = current_offset,
    };
}

next_token :: (using lexer: *Lexer) -> Token {
    token := make_token(lexer, .UNKNOWN, 0);

    while true {
        ok, c := peek_char(lexer);
        if !ok {
            token.kind = .EOF;
            break;
        }

        if #complete mode == {
        case .OUTSIDE;
            if c == #char "<" {
                mode = .INSIDE_TAG;
                break;
            } else {
                token.kind = .TEXT;
                consume(lexer, 1);
                token.text.count += 1;
            }
        case .INSIDE_TAG;
            token.text.count += 1;
            consume(lexer, 1);
            _, c1 := peek_char(lexer);
            if c == {
            case #char "<";
                if c1 ==  {
                case #char "/";
                    token.kind = .CLOSE_TAG_START;
                    token.text.count += 1;
                    consume(lexer, 1);
                    break;
                case #char "!";
                    token.text.count += 1;
                    consume(lexer, 1);
                    _, c2 := peek_char(lexer);
                    if c2 == {
                    case #char "-";
                        // Comment
                        _, s := peek_string(lexer, 2);
                        if s == "--" {
                            consume(lexer, 2);
                            token.kind = .COMMENT;
                            mode = .INSIDE_COMMENT;
                        } else {
                            _, s = peek_string(lexer, 7);
                            if s == "[CDATA[" {
                                consume(lexer, 7);
                                token.kind = .CDATA;
                                mode = .INSIDE_CDATA;
                            } else if s == "DOCTYPE" {
                                consume(lexer, 7);
                                token.kind = .DOCTYPE;
                                mode = .INSIDE_DOCTYPE;
                            } else {
                                token.kind = .UNKNOWN;
                                break;
                            }
                        }
                    }
                case #char "?";
                    token.text.count += 1;
                    consume(lexer, 1);

                    token.kind = .PROCESSING_INSTRUCTION_START;
                    break;
                case;
                    token.kind = .OPEN_TAG_START;
                    break;
                }

            case #char "\"";
                token.kind = .ATTRIBUTE_VALUE;
                mode = .INSIDE_ATTRIBUTE_VALUE;
            case #char "=";
                token.kind = .EQUALS;
                break;
            case #char "?";
                _, c1 := peek_char(lexer);
                if c1 == #char ">" {
                    token.kind = .PROCESSING_INSTRUCTION_END;
                    token.text.count += 1;
                    consume(lexer, 1);
                    break;
                }
            case #char "/";
                _, c1 := peek_char(lexer);
                if c1 == #char ">" {
                    token.kind = .SELF_CLOSING_END;
                    token.text.count += 1;
                    consume(lexer, 1);
                    break;
                }
            case #char ">";
                token.kind = .TAG_END;
                break;
            case;
                token.kind = .NAME;
            }

        case .INSIDE_ATTRIBUTE_VALUE;
            token.text.count += 1;
            consume(lexer, 1);
            if c == #char "\"" {
                mode = .INSIDE_TAG;
                break;
            }
        case .INSIDE_DOCTYPE;
            token.text.count += 1;
            consume(lexer, 1);

            if c == {
            case #char "[";
                mode = .INSIDE_DOCUMENT_TYPE_DEFINITION;
            case #char ">";
                mode = .OUTSIDE;
                break;
            case;
            // Do nothing
            }
        case .INSIDE_DOCUMENT_TYPE_DEFINITION;
            token.text.count += 1;
            consume(lexer, 1);
            if c == "]" {
                mode = .INSIDE_DOCTYPE;
            }
        case .INSIDE_CDATA;
            if c == #char "]" {
                _, s := peek_string(lexer, 3);
                if s == "]]>" {
                    consume(lexer, 3);
                    mode = .OUTSIDE;
                    break;
                }
            }
        case .INSIDE_COMMENT;
            if c == #char "-" {
                _, s := peek_string(lexer, 3);
                if s == "-->" {
                    mode = .OUTSIDE;
                    token.text.count += 3;
                    consume(lexer, 3);
                    break;
                }
            }

            consume(lexer, 1);
        }
    }

    return token;
}

handle_outside :: (using lexer: *Lexer, token: *Token) {

}

#import "String";
#import "Basic";
