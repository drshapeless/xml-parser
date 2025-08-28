// This program intentionally does not free any of the string it created.

// In vk.xml, there are somehow two sets of API mixing together. One
// is vulkan and one is vulkansc. This leads to redundant occurence of
// type, parameter and functions. I have to deal with them here and
// there to remove them when detecting an attribute of api="vulkansc".

Buffers :: struct {
    types: String_Builder;
    structs: String_Builder;
    constants: String_Builder;
    enums: String_Builder;
    functions: String_Builder;
}

main :: () {
    source_string, ok := read_entire_file("vk.xml");
    if !ok {
        log_error("vk.xml not found");
    }

    at := current_time_monotonic();
    start_time := to_float64_seconds(at);

    root := parse_xml(source_string);

    buffers: Buffers;

    gen_types(root, *buffers);

    write_entire_file("types.jai", *buffers.types);
    write_entire_file("structs.jai", *buffers.structs);
    write_entire_file("constants.jai", *buffers.constants);
    write_entire_file("enums.jai", *buffers.enums);
    write_entire_file("functions.jai", *buffers.functions);

    at = current_time_monotonic();
    end_time := to_float64_seconds(at);
    log("Finished in % seconds", end_time - start_time);
}

gen_types :: (node: Node, buffers: *Buffers) {
    for child: node.children {
        if child.tag_name == "types" {
            for type_node : child.children {
                if type_node.tag_name == "type" {
                    if is_vulkansc(type_node) {
                        continue;
                    }
                    category := get_attr(type_node, "category");
                    if category == {
                    case "bitmask";
                        generate_bitmask(type_node, *buffers.types);
                    case "handle";
                        generate_handle(type_node, *buffers.types);
                    case "funcpointer";
                        generate_funcpointer(type_node, *buffers.types);
                    case "struct";
                        generate_struct(type_node, *buffers.structs);
                    }
                }
            }
        } else if child.tag_name == "enums" {
            type := get_attr(child, "type");
            if type == {
            case "constants";
                for enum_node : child.children {
                    generate_enum_constants(enum_node, *buffers.constants);
                }
            case "enum";
                generate_enum(child, *buffers.enums);
            case "bitmask";
                generate_enum_bitmask(child, *buffers.enums);
            }
        } else if child.tag_name == "commands" {

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
"float",
"double",
];

C_TYPE_SIZES :: int.[
8,
16,
32,
64,
8,
16,
32,
64,
8,
64,
32,
64,
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
"float",
"float64",
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

        bitmask_handler : Struct_Bitmask_Handler;

        // member_node is probably a bad name because it may not be a
        // member. But in today, Aug 25 2025, all the children of a
        // struct node is member.
        for member_node: node.children {
            // This check is redundant.
            if member_node.tag_name == "member" {
                if is_vulkansc(member_node) {
                    continue;
                }
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

                            if bitmask_handler.max_size == 0 {
                                // The type should have parsed at this point.
                                type_name := type_node.inner_string;
                                type_size := get_c_type_size(type_name);

                                bitmask_handler.max_size = type_size;
                            }

                            // I am lazy, I don't check error.
                            bit_size := string_to_int(trim_left(s, ":"));
                            assert(bit_size != 0, "bit size should never be zero, you are fucked!");
                            bitmask_handler.current_size += bit_size;
                            append(*bitmask_handler.saved_string, "    ");
                            append(*bitmask_handler.saved_string, name_node.inner_string);
                            append(*bitmask_handler.saved_string, " : ");
                            append(*bitmask_handler.saved_string, type_conversion(type_node.inner_string));
                            append(*bitmask_handler.saved_string, ";");
                            append(*bitmask_handler.saved_string, sprint(" /* % bit */\n", bit_size));


                            assert(bitmask_handler.current_size <= bitmask_handler.max_size ,"bitmask current size cannot be bigger than max size");


                            if bitmask_handler.current_size == bitmask_handler.max_size {
                                // Now we export a bit field to the main struct
                                bitmask_handler.done = true;
                            }

                            // log("bitfield detected, struct: %, member: %, bitfield: %", struct_name, name_node.inner_string, s);
                        }
                    }
                }

                if bitmask_handler.done {
                    append(sb, "    __bitfield: ");
                    append(sb, sprint("u%;\n", bitmask_handler.max_size));
                    append(sb, "/*\n");
                    append(sb, builder_to_string(*bitmask_handler.saved_string));
                    append(sb, "*/\n");
                    bitmask_handler = .{};
                } else if bitmask_handler.max_size == 0 {
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
        }
        append(sb, "}\n\n");
    }
}

get_c_type_size :: (type: string) -> int {
    for c_type, index : C_TYPE_NAMES {
        if c_type == type {
            return C_TYPE_SIZES[index];
        }
    }

    return 0;
}

Struct_Bitmask_Handler :: struct {
    saved_string: String_Builder;
    max_size: int;
    current_size: int;
    done: bool;
}

generate_enum_constants :: (node: Node, sb: *String_Builder) {
    name := get_attr(node, "name");
    type := type_conversion(get_attr(node, "type"));
    value := trim(get_attr(node, "value"), "()ULF");

    append(sb, name);
    append(sb, " : ");
    append(sb, type);
    append(sb, " : ");

    if begins_with(value, "~") {
        append(sb, "~cast(");
        append(sb, type);
        append(sb, ")");
        append(sb, trim_left(value, "~"));
    } else {
        append(sb, value);
    }
    append(sb, ";\n");
}

generate_enum :: (node: Node, sb: *String_Builder) {
    enum_name := get_attr(node, "name");

    append(sb, enum_name);
    append(sb, " :: enum s32 #specified {\n");

    for member_node : node.children {
        if member_node.tag_name == "enum" {
            name := get_attr(member_node, "name");
            value := get_attr(member_node, "value");
            comment := get_attr(member_node, "comment");

            append(sb, "    ");
            append(sb, name);
            append(sb, " :: ");
            if value.count > 0 {
                append(sb, value);
            } else {
                alias := get_attr(member_node, "alias");
                assert(alias.count > 0);
                append(sb, alias);
            }
            append(sb, ";");

            if comment.count > 0 {
                append(sb, " /* ");
                append(sb, comment);
                append(sb, " */");
            }

            append(sb, "\n");
        } else if member_node.tag_name == "comment" {
            append(sb, "/* ");
            append(sb, member_node.inner_string);
            append(sb, " */\n");
        }
    }

    append(sb, "}\n\n");
}

generate_enum_bitmask :: (node: Node, sb: *String_Builder) {
    enum_name := get_attr(node, "name");

    enum_type := "u32";
    bitwidth := get_attr(node, "bitwidth");
    if bitwidth == "64" {
        enum_type = "u64";
    }

    append(sb, enum_name);
    append(sb, " :: enum_flags ");
    append(sb, enum_type);
    append(sb, " {\n");

    for member_node : node.children {
        if member_node.tag_name == "enum" {
            name := get_attr(member_node, "name");
            value := get_attr(member_node, "value");
            bitpos := get_attr(member_node, "bitpos");

            append(sb, "    ");
            append(sb, name);
            append(sb, " :: ");

            if value.count > 0 {
                append(sb, value);
            } else if bitpos.count > 0 {
                append(sb, "1 << ");
                append(sb, bitpos);
            } else {
                alias := get_attr(member_node, "alias");
                assert(alias.count > 0);
                append(sb, alias);
            }

            append(sb, ";\n");
        } else if member_node.tag_name == "comment" {
            append(sb, "/* ");
            append(sb, member_node.inner_string);
            append(sb, " */\n");
        }
    }

    append(sb, "}\n\n");
}

is_vulkansc :: (node: Node) -> bool {
    api := get_attr(node, "api");
    if api == "vulkansc" {
        return true;
    }

    return false;
}

generate_commands :: (node: Node, sb: *String_Builder) {
    for command_node : node.children {

    }
}

#import "Basic";
#import "File";
#import "String";

#import,file "../module.jai";
