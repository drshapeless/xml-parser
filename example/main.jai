main :: () {
    source_string, ok := read_entire_file("vk.xml");
    if !ok {
        log_error("vk.xml not found");
    }

    at := current_time_monotonic();
    start_time := to_float64_seconds(at);

    root := parse_xml(source_string);

    types_node := find_first_child_of_tag_name(root, "types");
    assert(types_node != null);

    sb: String_Builder;

    gen_types(types_node, *sb);

    write_entire_file("types.jai", *sb);

    at = current_time_monotonic();
    end_time := to_float64_seconds(at);
    log("Finished in % seconds", end_time - start_time);
}

gen_types :: (node: Node, sb: *String_Builder) {
    for child: node.children {
        category := get_attr(child, "category");
        if category == {
        case "bitmask";
            if is_self_close_node(child) {
                name := get_attr(child, "name");
                alias := get_attr(child, "alias");
                append(sb, sprint("% :: %;\n", name, alias));
            } else {
                name_node := find_first_child_of_tag_name(child, "name");
                name := name_node.inner_string;

                type_node := find_first_child_of_tag_name(child, "type");
                type := type_node.inner_string;
                append(sb, sprint("% :: %;\n", name, type));
            }
        case "handle";
            if is_self_close_node(child) {
                name := get_attr(child, "name");
                alias := get_attr(child, "alias");
                append(sb, sprint("% :: %;\n", name, alias));
            } else {
                name_node := find_first_child_of_tag_name(child, "name");
                name := name_node.inner_string;
                type_node := find_first_child_of_tag_name(child, "type");
                type := type_node.inner_string;

                if type == "VK_DEFINE_HANDLE" {
                    append(sb, sprint("% :: *void;\n", name));
                } else if type == "VK_DEFINE_NON_DISPATCHABLE_HANDLE" {
                    append(sb, sprint("% :: u64;\n", name));
                } else {
                    assert(false, "you should not be here %", child);
                }
            }
        case "funcpointer";
            name_index := find_first_index_of_tag_name(child, "name");
            if name_index < 0 {
                log("funcpointer error: %", child);
                continue;
            }
            name := child.children[name_index].inner_string;
            log("func: %", name);

            // There is a fucking open brace
            index := name_index + 2;
            while index < child.children.count {
                type_node := child.children[index];
                assert(type_node.tag_name == "type", "funcpointer error, the tagname is %: %", type_node.tag_name, child.raw_string);
                parameter_node := child.children[index + 1];
                assert(parameter_node.type == .PLAIN, "funcpointer error: %", child.raw_string);
                log("    %", type_node.inner_string);
                log("    %", parameter_node.raw_string);
                index += 2;
            }

        }
    }
}

#import "Basic";
#import "File";
#import "String";

#import,file "../module.jai";
