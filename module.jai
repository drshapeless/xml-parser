parse_xml :: (s: string) -> Node {
    tokens := tokenize(s);
    node := read_tokens(tokens);

    return node;
}

find_first_child_of_tag_name :: (node: Node, name: string) -> *Node {
    for child : node.children {
        if child.type == .NODE && child.tag_name == name {
            return *child;
        }
    }

    return null;
}

// Return -1 when not found.
find_first_index_of_tag_name :: (node: Node, name: string) -> int {
    for index: 0..node.children.count - 1 {
        child := node.children[index];
        if child.type == .NODE && child.tag_name == name {
            return index;
        }
    }
    return -1;
}

get_attr :: (node: Node, key: string) -> string {
    for attr: node.attrs {
        if attr.key == key {
            return attr.value;
        }
    }

    return "";
}

is_self_close_node :: (node: Node) -> bool {
    return node.children.count == 0;
}

#scope_file

#load "tokenizer.jai";
