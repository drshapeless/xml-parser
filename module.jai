Node_Type :: enum u8 {
    NODE;
    PLAIN;
}

Node :: struct {
    type: Node_Type;
    depth: s32;
    parent: *Node;

    str: string; // This is like innerHTML
    tag: Tag;
    children: [..] Node;

    raw: string;

    done := false;
}

parse_xml :: (s: string) -> Node {
    lexer: Lexer;
    set_input_from_string(*lexer, s);

    root: Node;

    current: *Node = null;

    while 1 {
        token := get_token(*lexer);
        if token.type == {
        case .EOF;
            #through;
        case .ERROR;
            break;
        case .TAG;
            if #complete token.tag.type == {
            case .DECLARATION;
                #through;
            case .COMMENT;
                continue;
            case .OPEN;
                if current != null {
                    new_node := Node.{
                        type = .NODE,
                        depth = current.depth + 1,
                        parent = current,
                        tag = token.tag
                    };

                    array_add(*current.children, new_node);
                    current = *current.children[current.children.count - 1];
                } else {
                    root.type = .NODE;
                    root.tag = token.tag;
                    current = *root;
                }
            case .CLOSE;
                if current.tag.name != token.tag.name {
                    report_parse_error(*lexer, *token, "Unmatch close tag, expect %, get %", current.tag.name, token.tag.name);
                    break;
                }

                if current.done == true {
                    report_parse_error(*lexer, *token, "Extra close tag");
                    break;
                }

                current.done = true;
                if current.parent == null {
                    // We are at the root node
                    break;
                }

                current.str = token.str;
                current = current.parent;
            case .SELF_CLOSE;
                new_node := Node.{
                    depth = current.depth + 1,
                    done = true,
                    type = .NODE,
                    tag = token.tag,
                    parent = current
                };
                array_add(*current.children, new_node);
            }
        case .INNER;
            new_node := Node.{
                depth = current.depth + 1,
                done = true,
                type = .PLAIN,
                parent = current,
                str = token.str
            };
            array_add(*current.children, new_node);
        }
    }

    return root;
}

find_node_of_tag_name :: (parent: Node, name: string, index: int = 0) -> *Node, int {
    if index < parent.children.count {
        for i : index..parent.children.count - 1 {
            child := *parent.children[i];
            if child.type == .NODE && child.tag.name == name {
                return child, i;
            }
        }
    }

    return null, -1;
}

get_attr :: (node: Node, key: string) -> string, bool {
    for attr: node.tag.attrs {
        if attr.key == key {
            return attr.value, true;
        }
    }

    return "", false;
}

is_self_close_node :: (node: Node) -> bool {
    return node.tag.type == .SELF_CLOSE;
}

#import "Basic";
#import "String";
#import,file "lexer.jai";
