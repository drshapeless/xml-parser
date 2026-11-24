XML :: struct {

}

parse_xml :: (s: string) -> XML {
    xml: XML;

    lexer: Lexer;
    lexer.document = s;

    while true {
        token := next_token(*lexer);
        if token.kind == .EOF {
            log("% % %", lexer.current_line, lexer.current_column, lexer.current_offset);
            break;
        }
    }

    return xml;
}

#load "lexer.jai";
