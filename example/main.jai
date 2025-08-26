// This program intentionally does not free any of the string it created.

Buffers :: struct {
    types: String_Builder;
    structs: String_Builder;
}

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

    buffers: Buffers;

    gen_types(types_node, *buffers);

    write_entire_file("types.jai", *buffers.types);
    write_entire_file("structs.jai", *buffers.structs);

    at = current_time_monotonic();
    end_time := to_float64_seconds(at);
    log("Finished in % seconds", end_time - start_time);
}

gen_types :: (node: Node, buffers: *Buffers) {
    for child: node.children {
        category := get_attr(child, "category");
        if category == {
        case "bitmask";
            generate_bitmask(child, *buffers.types);
        case "handle";
            generate_handle(child, *buffers.types);
        case "funcpointer";
            generate_funcpointer(child, *buffers.types);
        case "struct";
            generate_struct(child, *buffers.structs);
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

// This count the number of prefix *
count_pointer :: (s: string, prefix_only: bool = true) -> int {
    cnt := 0;
    for c : s {
        if c == #char "*" {
            cnt += 1;
        } else if prefix_only {
            break;
        }
    }

    return cnt;
}

// Move the * from back to front
move_pointer_to_front :: (s: string) -> string {
    cnt := count_pointer(s, false);

    ss := trim_right(s, "*");

    sb: String_Builder;
    while cnt > 0 {
        append(*sb, "*");
        cnt -= 1;
    }
    append(*sb, ss);

    return builder_to_string(*sb);
}

generate_funcpointer :: (node: Node, sb: *String_Builder) {
    name_node, name_index := find_node_of_tag_name(node, "name");
    if name_index < 0 {
        log("funcpointer error: %", node);
        return;
    }
    name := name_node.inner_string;
    // This is hardcoded to be the first child
    return_type_node := node.children[0];
    ss := split(return_type_node.raw_string, " ");
    return_type_name := ss[1];
    append(sb, name);
    append(sb, " :: #type (");

    index := name_index + 1;
    members : [..] string;
    while index < node.children.count {
        type_node, type_index := find_node_of_tag_name(node, "type", index);
        if type_node == null {
            break;
        }
        type_name := type_node.inner_string;
        type_name = type_conversion(type_name);

        parameter_node := node.children[type_index + 1];
        parameter_name := parameter_node.raw_string;
        number_of_pointer := count_pointer(parameter_name);
        parameter_name = clean_parameter_name(parameter_name);

        temp_sb: String_Builder;
        append(*temp_sb, parameter_name);
        append(*temp_sb, ": ");
        for 0..number_of_pointer - 1 {
            append(*temp_sb, "*");
        }
        append(*temp_sb, type_name);

        member := builder_to_string(*temp_sb);
        array_add(*members, member);

        index = type_index + 2;
    }
    append(sb, join(..members, ", "));
    append(sb, ") -> ");
    append(sb, move_pointer_to_front(return_type_name));
    append(sb, " #c_call;\n");
}

generate_handle :: (node: Node, sb: *String_Builder) {
    if is_self_close_node(node) {
        name := get_attr(node, "name");
        alias := get_attr(node, "alias");
        append(sb, sprint("% :: %;\n", name, alias));
    } else {
        name_node := find_node_of_tag_name(node, "name");
        name := name_node.inner_string;
        type_node := find_node_of_tag_name(node, "type");
        type := type_node.inner_string;

        if type == "VK_DEFINE_HANDLE" {
            append(sb, sprint("% :: *void;\n", name));
        } else if type == "VK_DEFINE_NON_DISPATCHABLE_HANDLE" {
            append(sb, sprint("% :: u64;\n", name));
        } else {
            assert(false, "you should not be here %", node);
        }
    }
}

generate_bitmask :: (node: Node, sb: *String_Builder) {
    if is_self_close_node(node) {
        name := get_attr(node, "name");
        alias := get_attr(node, "alias");
        append(sb, sprint("% :: %;\n", name, alias));
    } else {
        name_node := find_node_of_tag_name(node, "name");
        name := name_node.inner_string;

        type_node := find_node_of_tag_name(node, "type");
        type := type_node.inner_string;
        append(sb, sprint("% :: %;\n", name, type));
    }
}

generate_struct :: (node: Node, sb: *String_Builder) {
    struct_name := get_attr(node, "name");
    if is_self_close_node(node) {
        alias := get_attr(node, "alias");
        append(sb, struct_name);
        append(sb, " :: ");
        append(sb, alias);
        append(sb, ";\n");
    } else {
        append(sb, struct_name);
        append(sb, " :: struct {\n");

        // member_node is probably a bad name because it may not be a
        // member. But in today, Aug 25 2025, all the children of a
        // struct node is member.
        for member_node: node.children {
            // This check is redundant.
            if member_node.tag_name == "member" {
                type_node : *Node;
                name_node : *Node;
                is_square_bracket_begin := false;
                is_square_bracket_done := false;
                type_prefix := "";
                number_of_pointer := 0;
                for member_child_node : member_node.children {
                    if member_child_node.type == .NODE {
                        if member_child_node.tag_name == {
                        case "type";
                            type_node = *member_child_node;
                        case "comment";
                            // Do nothing
                            ;
                        case "enum";
                            if is_square_bracket_begin {
                                assert(!is_square_bracket_done, "Something wrong in struct: %, member: %", struct_name, type_node.inner_string);
                                type_prefix = sprint("[%]", member_child_node.inner_string);
                            }
                        case "name";
                            name_node = *member_child_node;
                        }
                    } else {
                        s := member_child_node.raw_string;
                        s = trim(s);

                        if begins_with(s, "[") {
                            if ends_with(s, "]") {
                                // Here should be something like this [3] or [3][4]
                                type_prefix = s;
                            } else {
                                assert(s.count == 1, "Something wrong in struct: %, member: %", struct_name, name_node.inner_string);
                                is_square_bracket_begin = true;
                            }
                        } else if begins_with(s, "*") {
                            number_of_pointer = count_pointer(s);
                        } if begins_with(s, "]") {
                            assert(s.count == 1, "Something wrong in struct: %, member: %", struct_name, name_node.inner_string);
                            is_square_bracket_done = true;
                        } else if contains(s, ":") {
                            // I hate Nvidia for making things
                            // complicated by introducing bitfield.
                            log("bitfield detected, struct: %, member: %, bitfield: %", struct_name, name_node.inner_string, s);
                        }
                    }
                }

                assert(type_node != null);
                type_name := type_node.inner_string;
                assert(name_node != null);
                parameter_name := name_node.inner_string;

                append(sb, "    ");
                append(sb, parameter_name);
                append(sb, ": ");
                while number_of_pointer > 0 {
                    append(sb, "*");
                    number_of_pointer -= 1;
                }
                append(sb, type_prefix);
                append(sb, type_conversion(type_name));
                append(sb, ";\n");
            }
        }
        append(sb, "}\n\n");
    }
}

Struct_Bitmask_Handler :: struct {
    saved_string: string;
    max_size: int;
    current_size: int;
}

#import "Basic";
#import "File";
#import "String";

#import,file "../module.jai";
