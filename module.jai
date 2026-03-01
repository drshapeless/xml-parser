// This library structure is inspired by Anton Mikhailov's Large Array of Thing
Node :: struct {
    IDX :: #type s64;

    Node_Type :: enum {
        NIL;
        ELEMENT;
        ATTRIBUTE;
        CONTENT;
    }

    Attribute :: struct {
        key: string;
        value: string;
    }

    Element :: struct {
        name: string;
    }

    type: Element_Type;

    union {
        element: Element;
        attribute: Attribute;
        content: string;
    }

    parent_idx: IDX;
    first_child_idx: IDX;
    first_attribute_idx: IDX;

    // Ring structure, the last item points to the first. This should
    // eliminate the need of last_child_idx, but it has to transverse
    // all the children in order to add a new sibling, and that may be
    // slow?
    //
    // Need testing
    next_sibling_idx: IDX;
}

XML :: struct {
    // We have no idea how many nodes are there, so this cannot be preallocated.
    nodes: [..] Node;

    // We have a string buffer that stores all the string in the whole xml
    //
    // We don't care about how big the string buffer is, all we know
    // is that it must be enough to hold all the string allocation in
    // XML
    string_buffer: *u8;
    string_buffer_cursor: *u8;
}

parse_xml :: (s: string) -> XML {
    lexer: Lexer;
    lexer.input = s;

    xml: XML;
    init_xml(*xml, s.count);

    previous_token: Token;

    current_idx: Node.IDX;
    is_inside_tag := false;
    is_tag_closed := true;

    while !lexer.reported_error {
        token := get_token(*lexer);
        if token.type == {
        case .EOF;
            break;
        case .ERROR;
            report_parse_error(*lexer, token, "Token error");
        case .L_BRACKET;
            if current_idx == 0 {
                current_node := Node.{
                    type = .ELEMENT
                };
                current_idx = make_node(*xml, current_node);
                is_inside_tag = true;
                is_tag_closed = false;
            } else if is_inside_tag {
                report_parse_error(*lexer, token, "Found a L_BRACKET inside a tag");
            } else if is_tag_closed {
                // A child

                current_idx = add_child(*xml, current_node_idx, .{type = .ELEMENT});

                is_inside_tag = true;
                is_tag_closed = false;
            } else {

            }
        }
    }

    return xml;
}

#scope_file
// The string size should be the file size of the input string of the lexer
init_xml :: (xml: *XML, string_size: u64) {
    xml.string_buffer = alloc(string_size);
    xml.string_buffer_cursor = xml.string_buffer;

    // here we append an empty node as the nil thing
    empty_node: Node;
    array_add(*xml.nodes, empty_node);
}

make_node :: (xml: *XML, node: Node) -> Node.IDX {
    array_add(*xml.nodes, node);

    return xml.nodes.count - 1;
}

get_node :: (xml: *XML, idx: Node.IDX) -> *Node {
    return *xml.nodes[idx];
}

get_last_child_idx :: (xml: *XML, idx: Node.IDX) -> Node.IDX {
    root_node := get_node(xml, idx);

    if root_node.first_child_idx == 0 {
        return 0;
    }

    current_node_idx := root_node.first_child_idx;
    while true {
        current_node := get_node(xml, current_node_idx);

        // Don't check 0 for now
        if current_node.next_sibling_idx == root_node.first_child_idx {
            return curret_node_idx;
        }

        current_node_idx = current_node.next_sibling_idx;
    }

    return 0;
}

// return child idx
add_child :: (xml: *XML, parent_idx: Node.IDX, child: Node) -> Node.IDX {
    current_child_idx := make_node(xml, child);
    parent_node := get_node(xml, parent_idx);

    current_child := get_node(xml, current_child_idx);
    current_child.parent_idx = parent_idx;

    last_child_idx := get_last_child_idx(xml, parent_idx);
    if last_child_idx {
        last_child := get_node(xml, last_child_idx);
        last_child.next_sibling_idx = current_child_idx;
    } else {
        parent_node.first_child_idx = current_child_idx;
    }
    current_child.next_sibling_idx = parent_node.first_child_idx;

    return current_child_idx;
}

make_string :: (xml: *XML, s: string) -> string {
    new_string: string;

    new_string.data = xml.string_buffer_cursor;
    new_string.count = s.count;

    memcpy(new_string.data, s.data, s.count);

    xml.string_buffer_cursor += s.count;

    return new_string;
}



#import "Basic";
#import,file "lexer.jai";
#import "String";
