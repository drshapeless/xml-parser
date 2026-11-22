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
    ERROR;
    OUTSIDE;
    INSIDE_TAG;
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

// If the offset exceed the document count, return 0.
peek_char :: (using lexer: *Lexer, offset: s64 = 0) -> u8 {
    i := current_offset + offset;

    if i < document.count {
        return document[i];
    } else {
        return 0;
    }
}

peek_string :: (using lexer: *Lexer, count: s64) -> string {
    if current_offset + count >= document.count {
        return "";
    } else {
        return slice(document, current_offset, count);
    }
}

consume :: (using lexer: *Lexer, count: s64) {
    while 0..count-1 {
        c := peek_char(lexer);

        if c == {
        case #char "\n";
            current_line += 1;
            current_column = 1;
        case 0;
            return;
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
    while outer := true {
        c := peek_char(lexer);
        if c == 0 {
            token.kind = .EOF;
            break;
        }

        if #complete mode == {
        case .ERROR;
            break outer;
        case .OUTSIDE;
            if c == {
            case #char "<";
                c1 := peek_char(lexer, 1);
                if c1 == {
                case #char "/";
                    token.kind = .CLOSE_TAG_START;
                    token.text = slice(document, token.offset, 2);
                    consume(lexer, 2);
                    mode = .INSIDE_TAG;
                    break outer;

                case #char "?";
                    token.kind = .PROCESSING_INSTRUCTION_START;
                    token.text = slice(document, token.offset, 2);
                    consume(lexer, 2);
                    mode = .INSIDE_TAG;
                    break outer;

                case #char "!";
                    consume(lexer, 2);
                    token.text.count += 2;
                    c = peek_char(lexer);
                    if c == {
                    case #char "-";
                        c1 := peek_char(lexer, 1);
                        if c1 == #char "-" {
                            token.kind = .COMMENT;
                            token.text.count += 2;
                            consume(lexer, 2);
                            mode = .INSIDE_COMMENT;

                        } else {
                            // This should be a malformed XML.
                            mode = .ERROR;
                            break outer;
                        }
                    case #char "D";
                        s := peek_string(lexer, 7);
                        if s == "DOCTYPE" {
                            token.kind = .DOCTYPE;
                            token.text.count += 7;
                            consume(lexer, 7);
                            mode = .INSIDE_DOCTYPE;
                        } else {
                            mode = .ERROR;
                            break outer;
                        }
                    case #char "[";
                    // Only CDATA is valid here
                        s := peek_string(lexer, 7);
                        if s == "[CDATA[" {
                            token.kind = .CDATA;
                            token.text.count += 7;
                            consume(lexer, 7);
                            mode = .INSIDE_CDATA;
                        } else {
                            mode = .ERROR;
                            break outer;
                        }
                    case;
                        mode = .ERROR;
                        break outer;
                    }
                }
            case;
                token.text.count += 1;
                consume(lexer, 1);
            }

        case .INSIDE_TAG;
            if c == {
            case #char "\"";
                token.kind = .ATTRIBUTE_VALUE;
                token.text.count += 1;
                consume(lexer, 1);
                while peek_char(lexer) != #char "\"" {
                    consume(lexer, 1);
                    token.text.count += 1;
                }
                consume(lexer, 1);
                token.text.count += 1;
                break outer;
            case #char "=";
                token.kind = .EQUALS;
                token.text.count = 1;
                consume(lexer, 1);
            case;
                if is_space(c) {
                    consume(lexer, 1);
                } else {
                    token.kind = .NAME;
                    while !is_space(peek_char(lexer)) {
                        token.text.count += 1;
                        consume(lexer, 1);
                    }
                    break outer;
                }
            }

        case .INSIDE_DOCTYPE;
        case .INSIDE_DOCUMENT_TYPE_DEFINITION;

        case .INSIDE_CDATA;

        case .INSIDE_COMMENT;
            if c == #char "-" {
                s := peek_string(lexer, 3);
                if s == "-->" {
                    token.text.count += 3;
                    consume(lexer, 3);

                }
            } else {
                token.text.count += 1;
                consume(lexer, 1);
            }
        }

    }

    return token;
}

#import "String";
#import "Basic";
