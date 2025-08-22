main :: () {
    source_string, ok := read_entire_file("vk.xml");
    if !ok {
        log_error("vk.xml not found");
    }

    node := parse_xml(source_string);

    log("children count %", node.children.count);

    types_node := xml_find_first_child_of_tag_name(node, "types");
    assert(types_node != null);

    log("types children count %", types_node.children.count);

    if types_node.type == {
    case .NODE;
        log("");
        log("");
    case .PLAIN;

    }
}


#import "Basic";
#import "File";
#import "String";

#load "module.jai";
