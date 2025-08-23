main :: () {
    source_string, ok := read_entire_file("vk.xml");
    if !ok {
        log_error("vk.xml not found");
    }

    at := current_time_monotonic();
    start_time := to_float64_seconds(at);

    root := parse_xml(source_string);

    types_node := find_node_of_tag_name(root, "types");
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
                name_node := find_node_of_tag_name(child, "name");
                name := name_node.inner_string;

                type_node := find_node_of_tag_name(child, "type");
                type := type_node.inner_string;
                append(sb, sprint("% :: %;\n", name, type));
            }
        case "handle";
            if is_self_close_node(child) {
                name := get_attr(child, "name");
                alias := get_attr(child, "alias");
                append(sb, sprint("% :: %;\n", name, alias));
            } else {
                name_node := find_node_of_tag_name(child, "name");
                name := name_node.inner_string;
                type_node := find_node_of_tag_name(child, "type");
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
            name_node, name_index := find_node_of_tag_name(child, "name");
            if name_index < 0 {
                log("funcpointer error: %", child);
                continue;
            }
            name := name_node.inner_string;
            log("func: %", name);

            index := name_index + 1;
            while index < child.children.count {
                type_node, type_index := find_node_of_tag_name(child, "type", index);
                if type_node == null {
                    break;
                }
                type_name := type_node.inner_string;
                type_name = type_conversion(type_name);

                parameter_node := child.children[type_index + 1];
                parameter_name := parameter_node.raw_string;
                is_pointer := begins_with(parameter_name, "*");
                parameter_name = clean_parameter_name(parameter_name);

                if is_pointer {
                    log("    %: *%", parameter_name, type_name);
                } else {
                    log("    %: %", parameter_name, type_name);
                }
                index = type_index + 2;
            }
        }
    }
}

DEFAULT_PARAMETER_TRIM :: "*,(); \n";

clean_parameter_name :: (s: string) -> string {
    i := find_index_from_left(s, "const");

    ss := s;
    if i >= 0 {
        ss = slice(s, 0, i);
    }

    return trim(ss, DEFAULT_PARAMETER_TRIM);
}

C_TYPE_NAMES :: string.[
"int8_t",
"int16_t",
"int32_t",
"int64_t",
"uint8_t",
"uint16_t",
"uint32_t",
"uint64_t",
"char",
"size_t",
];

JAI_TYPE_NAMES :: string.[
"s8",
"s16",
"s32",
"s64",
"u8",
"u16",
"u32",
"u64",
"u8",
"u64",
];

type_conversion :: (s: string) -> string {
    for t, i : C_TYPE_NAMES {
        if s == t {
            return JAI_TYPE_NAMES[i];
        }
    }

    return s;
}

#import "Basic";
#import "File";
#import "String";

#import,file "../module.jai";
