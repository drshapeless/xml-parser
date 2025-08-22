main :: () {
    source_string, ok := read_entire_file("vk.xml");
    if !ok {
        log_error("vk.xml not found");
    }

    root := parse_xml(source_string);

    types_node := xml_find_first_child_of_tag_name(root, "types");
    assert(types_node != null);

    for types_node.children {
        log("attr: %", it.attrs);
        category := xml_get_attr(it, "categroy");
        log("%", category);
        if category.count != 0 {
            if category == "define" {
                log("define: %", it.inner_string);
            }
        }
    }
}


#import "Basic";
#import "File";
#import "String";

#import,file "../module.jai";
