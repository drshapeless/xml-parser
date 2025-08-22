parse_xml :: (s: string) -> Node {
    tokens := tokenize(s);
    node := read_tokens(tokens);

    return node;
}

xml_find_first_child_of_tag_name :: (node: Node, name: string) -> *Node {
    for child : node.children {
        if child.type == .NODE && child.tag_name == name {
            return *child;
        }
    }

    return null;
}

#scope_file

#load "tokenizer.jai";
