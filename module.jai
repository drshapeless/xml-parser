parse_xml :: (s: string) -> Node {
    tokens := tokenize(s);
    node := read_tokens(tokens);

    return node;
}

find_node_of_tag_name :: (parent: Node, name: string, index: int = 0) -> *Node, int {
    if index < parent.children.count {
        for i : index..parent.children.count - 1 {
            child := *parent.children[i];
            if child.type == .NODE && child.tag_name == name {
                return child, i;
            }
        }
    }

    return null, -1;
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
