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

        }

        consume(lexer, 1);
    }

    return token;
}

#import "String";
#import "Basic";
