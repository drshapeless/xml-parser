main :: () {
    source_string, ok := read_entire_file("vk.xml");
    if !ok {
        log_error("vk.xml not found");
    }

    tokens := tokenize(source_string);

    for token: tokens {
        if token.type == .TAG {
            tag := parse_tag(token);
            log("tag type: %, tag name: %", tag.type, tag.name);
            for attr: tag.attrs {
                log("    key: %, value: %", attr.key, attr.value);
            }
        } else {
            log("this is a text");
        }
    }
}


#import "Basic";
#import "File";
#import "String";

#load "tokenizer.jai";
