VK_XML_PATH :: "vk.xml";

#run {
    set_build_options_dc(.{do_output = false});

    generate();
}

vk_types             : [..]VK_Type;
vk_structures        : [..]VK_Structure;
vk_functions         : [..]VK_Function;
vk_function_pointers : [..]VK_Function_Pointer;
vk_enums             : [..]VK_Enum;
vk_enum_flags        : [..]VK_Enum_Flags;
vk_constants         : [..]VK_Constant;

generate :: () {
    source_string, ok := read_entire_file("vk.xml");
    if !ok {
        log_error("vk.xml not found");
    }

    at := current_time_monotonic();
    start_time := to_float64_seconds(at);

    root_node := parse_xml(source_string);

    generation_loop(root_node);

    output_types();
    output_structures();
    output_functions();
    output_function_pointers();
    output_enums();
    output_enum_flags();
    output_constants();

    at = current_time_monotonic();
    end_time := to_float64_seconds(at);
    log("Vulkan binding generated in % seconds", end_time - start_time);
}

VK_Type :: struct {
    name  : string;
    alias : string;
    type  : string;
}

VK_Structure_Member :: struct {
    name              : string;
    number_of_pointer : int;
    array_prefix      : string;
    type              : string;
    bitmask           : int;
    comment           : string;
}

VK_Structure :: struct {
    name    : string;
    alias   : string;
    members : [..]VK_Structure_Member;
}

VK_Function_Param :: struct {
    name              : string;
    number_of_pointer : int;
    array_prefix      : string;
    type              : string;
}

VK_Function :: struct {
    name              : string;
    alias             : string;
    params            : [..]VK_Function_Param;
    number_of_pointer : int;
    return_type       : string;
}

VK_Function_Pointer :: VK_Function;

VK_Enum_Member :: struct {
    name    : string;
    alias   : string;
    value   : string;
    comment : string;
}

VK_Enum :: struct {
    name    : string;
    alias   : string;
    members : [..]VK_Enum_Member;
}

VK_Enum_Flags_Member :: struct {
    name   : string;
    value  : string;
    bitpos : string;
    alias  : string;
}

VK_Enum_Flags :: struct {
    name    : string;
    type    : string;
    members : [..]VK_Enum_Flags_Member;
}

VK_Constant :: struct {
    name  : string;
    type  : string;
    flip  : bool;
    value : string;
}

generation_loop :: (root_node: Node) {
    for root_child : root_node.children {
        if root_child.tag_name == {
        case "types";
            handle_types(root_child);
        case "enums";
            handle_enums(root_child);
        case "commands";
            handle_commands(root_child);
        }
    }
}

handle_types :: (parent: Node) {
    for type_node : parent.children {
        if is_vulkansc(type_node) {
            continue;
        }

        category := get_attr(type_node, "category");
        if category == {
        case "bitmask";
            handle_bitmask(type_node);
        case "handle";
            handle_handle(type_node);
        case "funcpointer";
            handle_funcpointer(type_node);
        case "struct";
            handle_struct(type_node);
        }
    }
}

handle_bitmask :: (node: Node) {
    using vk_type : VK_Type;

    if is_self_close_node(node) {
        name = get_attr(node, "name");
        alias = get_attr(node, "alias");
        assert(name.count > 0);
        assert(alias.count > 0);
    } else {
        for child : node.children {
            if child.type == .NODE {
                if child.tag_name == {
                case "name";
                    name = child.inner_string;
                case "type";
                    type = child.inner_string;
                case;
                    log("unhandled child in bitmask: %", node.raw_string);
                }
            }
        }

        assert(name.count > 0);
        assert(type.count > 0);
    }

    array_add(*vk_types, vk_type);
}

// What kind of cursed name this is
handle_handle :: (node: Node) {
    using vk_type : VK_Type;

    if is_self_close_node(node) {
        name = get_attr(node, "name");
        alias = get_attr(node, "alias");
        assert(name.count > 0);
        assert(alias.count > 0);
    } else {
        for child : node.children {
            if child.type == .NODE {
                if child.tag_name == {
                case "name";
                    name = child.inner_string;
                case "type";
                    type_string := child.inner_string;
                    if type_string == {
                    case "VK_DEFINE_HANDLE";
                        type = "*void";
                    case "VK_DEFINE_NON_DISPATCHABLE_HANDLE";
                        type = "u64";
                    case;
                        assert(false, "something wrong in handle: %", node.raw_string);
                    }
                case;
                    log("unhandled child in bitmask: %", node.raw_string);
                }
            }
        }

        assert(name.count > 0);
        assert(type.count > 0);
    }

    array_add(*vk_types, vk_type);
}


// The implementation of this function is not ideal, most of it is
// hardcoded, but there are not that many function pointer in vk.xml...
//
// In 2025 Aug 29, there is only 11 funcpointers.
handle_funcpointer :: (node: Node) {
    using vk_funcptr : VK_Function_Pointer;

    return_type_node := node.children[0];
    ss := split(return_type_node.raw_string, " ");
    return_type = ss[1];

    name_node, name_index := find_node_of_tag_name(node, "name");
    assert(name_index >= 0, "funcpointer error: %", node.raw_string);

    name = name_node.inner_string;

    index := name_index + 1;
    while index < node.children.count {
        param : VK_Function_Param;
        type_node, type_index := find_node_of_tag_name(node, "type", index);
        if type_node == null {
            break;
        }

        param.type = type_node.inner_string;
        param_node := node.children[type_index + 1];
        param.name = param_node.raw_string;
        number_of_pointer = count_pointer(param.name);
        param.name = clean_parameter_name(param.name);

        array_add(*params, param);

        index = type_index + 2;
    }

    array_add(*vk_function_pointers, vk_funcptr);
}

handle_struct :: (node: Node) {
    using vk_struct : VK_Structure;

    name = get_attr(node, "name");
    assert(name.count > 0);
    if is_self_close_node(node) {
        alias = get_attr(node, "alias");
        assert(alias.count > 0);
    } else {
        // member_node is probably a bad name because it may not be a
        // member. But in today, Aug 25 2025, all the children of a
        // struct node is member.
        for member_node : node.children {
            // This check is redundant.
            if member_node.tag_name == "member" {
                if is_vulkansc(member_node) {
                    continue;
                }

                vk_member : VK_Structure_Member;

                is_square_bracket_begin := false;
                is_square_bracket_done := false;
                for member_child : member_node.children {
                    if member_child.type == .NODE {
                        if member_child.tag_name == {
                        case "type";
                            vk_member.type = convert_type(member_child.inner_string);
                        case "comment";
                            vk_member.comment = member_child.inner_string;
                        case "enum";
                        // The only way that a enum node appears is as
                        // a enum constant to indicate a fixed array
                        // length.
                            vk_member.array_prefix = sprint("[%]", member_child.inner_string);
                        case "name";
                            vk_member.name = member_child.inner_string;
                        }
                    } else {
                        s := trim(member_child.raw_string);

                        if begins_with(s, "[") && ends_with(s, "]") {
                            vk_member.array_prefix = s;
                        } else if begins_with(s, "*") {
                            vk_member.number_of_pointer = count_pointer(s);
                        } else if contains(s, ":") {
                            // I hate Nvidia for making things
                            // complicated by introducing bitfield.

                            vk_member.bitmask = string_to_int(trim_left(s, ":"));
                        }
                    }
                }

                array_add(*vk_struct.members, vk_member);
            }
        }
    }

    array_add(*vk_structures, vk_struct);
}

handle_enums :: (parent: Node) {
    type := get_attr(parent, "type");
    if type == {
    case "constants";
        handle_enum_constants(parent);
    case "enum";
        handle_enum_enum(parent);
    case "bitmask";
        handle_enum_bitmask(parent);
    case;
        assert(false, "unhandled enum");
    }
}

handle_enum_constants :: (node: Node) {
    for enum_node : node.children {
        using c : VK_Constant;
        name = get_attr(enum_node, "name");
        type = convert_type(get_attr(enum_node, "type"));

        v := trim(get_attr(enum_node, "value"), "()ULF");

        flip = begins_with(v, "~");
        if flip {
            value = trim_left(v, "~");
        } else {
            value = v;
        }
        array_add(*vk_constants, c);
    }
}

// Another cursed name
handle_enum_enum :: (node: Node) {
    using vk_enum : VK_Enum;

    name = get_attr(node, "name");

    for member_node : node.children {
        vk_member : VK_Enum_Member;
        if member_node.tag_name == "enum" {
            vk_member.name = get_attr(member_node, "name");
            assert(vk_member.name.count > 0);

            vk_member.value = get_attr(member_node, "value");

            if vk_member.value.count == 0 {
                vk_member.alias = get_attr(member_node, "alias");
                assert(vk_member.alias.count > 0);
            }

            vk_member.comment = get_attr(member_node, "comment");
        } else if member_node.tag_name == "comment" {
            // If this is a standalone comment, we put it as a name.
            vk_member.name = member_node.inner_string;
        }

        array_add(*members, vk_member);
    }

    array_add(*vk_enums, vk_enum);
}

handle_enum_bitmask :: (node: Node) {
    using enum_flag : VK_Enum_Flags;

    name = get_attr(node, "name");
    assert(name.count > 0);

    bitwidth := get_attr(node, "bitwidth");
    if bitwidth == "64" {
        type = "u64";
    } else {
        type = "u32";
    }

    for member_node : node.children {
        member : VK_Enum_Flags_Member;
        if member_node.tag_name == "enum" {
            member.name = get_attr(member_node, "name");
            assert(member.name.count > 0);

            member.value  = get_attr(member_node, "value");
            member.bitpos = get_attr(member_node, "bitpos");
            member.alias  = get_attr(member_node, "alias");
        } else if member_node.tag_name == "comment" {
            // Same, if the member is a comment tag, put it in the name.
            member.name = member_node.inner_string;
        }

        array_add(*members, member);
    }

    array_add(*vk_enum_flags, enum_flag);
}

handle_commands :: (parent: Node) {
    for command_node : parent.children {
        if is_vulkansc(command_node) {
            continue;
        }

        command : VK_Function;
        if is_self_close_node(command_node) {
            command.name  = get_attr(command_node, "name");
            command.alias = get_attr(command_node, "alias");

            assert(command.name.count > 0);
            assert(command.alias.count > 0);
        } else {
            for member_node : command_node.children {
                if is_vulkansc(member_node) {
                    continue;
                }

                if member_node.tag_name ==  {
                case "proto";
                    for proto_child : member_node.children {
                        if proto_child.type == .NODE {
                            if proto_child.tag_name == {
                            case "type";
                                command.return_type = convert_type(proto_child.inner_string);
                            case "name";
                                command.name = proto_child.inner_string;
                            case;
                                log("unhandled node in %", command.name);
                            }
                        } else {
                            if begins_with(proto_child.raw_string, "*") {
                                command.number_of_pointer = count_pointer(proto_child.raw_string);
                            } else {
                                log("what is this? %", proto_child.raw_string);
                            }
                        }
                    }
                case "param";
                    param : VK_Function_Param;
                    for param_child : member_node.children {
                        if param_child.type == .NODE {
                            if param_child.tag_name == {
                            case "type";
                                param.type = convert_type(param_child.inner_string);
                            case "name";
                                param.name = param_child.inner_string;
                            }
                        } else {
                            if begins_with(param_child.raw_string, "*") {
                                param.number_of_pointer = count_pointer(param_child.raw_string);
                            } else if begins_with(param_child.raw_string, "[") && ends_with(param_child.raw_string, "]") {
                                param.array_prefix = param_child.raw_string;
                            }
                        }
                    }
                    array_add(*command.params, param);
                }
            }
        }
        array_add(*vk_functions, command);
    }
}

is_vulkansc :: (node: Node) -> bool {
    api := get_attr(node, "api");
    if api == "vulkansc" {
        return true;
    }

    return false;
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

convert_type :: (s: string) -> string {
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

get_c_type_size :: (type: string) -> int {
    for c_type, index : C_TYPE_NAMES {
        if c_type == type {
            return C_TYPE_SIZES[index];
        }
    }

    return 0;
}

get_jai_type_size :: (type: string) -> int {
    for j_type, index : JAI_TYPE_NAMES {
        if j_type == type {
            return C_TYPE_SIZES[index];
        }
    }

    return 0;
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

output_types :: () {
    sb: String_Builder;

    for t : vk_types {
        using t;
        append(*sb, name);
        append(*sb, " :: ");
        if alias.count > 0 {
            append(*sb, alias);
        } else {
            append(*sb, type);
        }
        append(*sb, ";\n");
    }

    write_entire_file("types.jai", *sb);
}


output_structure_member :: (member: VK_Structure_Member, sb: *String_Builder) {
    append(sb, "    ");
    append(sb, member.name);
    append(sb, ": ");
    n := member.number_of_pointer;

    while n > 0 {
        append(sb, "*");
        n -= 1;
    }

    append(sb, member.array_prefix);
    append(sb, member.type);
    append(sb, ";");
    if (member.comment.count > 0) {
        append(sb, " /* ");
        append(sb, member.comment);
        append(sb, " */");
    }

    append(sb, "\n");
}

output_structures :: () {
    sb: String_Builder;

    for structure : vk_structures {
        append(*sb, structure.name);
        append(*sb, " :: ");
        if structure.alias.count > 0 {
            append(*sb, structure.alias);
            append(*sb, ";\n");
        } else {
            append(*sb, "struct {\n");
            bitmask_target := 0;
            bitmask_type : string;
            bitmask_current := 0;
            bitmask_members : [..]VK_Structure_Member;

            for member : structure.members {
                if member.bitmask > 0 {
                    if bitmask_target == 0 {
                        bitmask_target = get_jai_type_size(member.type);
                        bitmask_type = member.type;
                    }

                    bitmask_current += member.bitmask;

                    array_add(*bitmask_members, member);

                    if bitmask_current == bitmask_target {
                        append(*sb, "    __bitmask: ");
                        append(*sb, bitmask_type);
                        append(*sb, "\n");
                        append(*sb, "    /*\n");
                        for bm : bitmask_members {
                            output_structure_member(bm, *sb);
                        }
                        append(*sb, "    */\n");
                        bitmask_target = 0;
                        bitmask_type = "";
                        bitmask_current = 0;
                        array_reset(*bitmask_members);
                    }
                    assert(bitmask_target == 0 || bitmask_current < bitmask_target);
                } else {
                    output_structure_member(member, *sb);
                }
            }
            append(*sb, "}\n");
        }

        append(*sb, "\n");
    }

    write_entire_file("structures.jai", *sb);
}

output_function_params :: (params: []VK_Function_Param, sb: *String_Builder) {
    is_beginning := true;
    for param : params {
        if is_beginning {
            is_beginning = false;
        } else {
            append(sb, ", ");
        }
        append(sb, param.name);
        append(sb, ": ");

        n := param.number_of_pointer;
        while n > 0 {
            append(sb, "*");
            n -= 1;
        }

        append(sb, param.array_prefix);
        append(sb, param.type);
    }
}

output_functions :: () {
    sb: String_Builder;

    for function : vk_functions {
        append(*sb, function.name);
        append(*sb, " :: ");
        if function.alias.count > 0 {
            append(*sb, function.alias);
            append(*sb, ";\n");
        } else {
            append(*sb, "(");

            output_function_params(function.params, *sb);

            append(*sb, ") -> ");
            n := function.number_of_pointer;
            while n > 0 {
                append(*sb, "*");
                n -= 1;
            }
            append(*sb, function.return_type);
            append(*sb, " #c_call;\n");
        }
    }

    write_entire_file("functions.jai", *sb);
}

output_function_pointers :: () {
    // If I remember correctly, there is not alias in function pointer

    sb: String_Builder;

    for function : vk_function_pointers {
        append(*sb, function.name);
        append(*sb, " :: #type (");

        output_function_params(function.params, *sb);

        append(*sb, ") -> ");
        n := function.number_of_pointer;
        while n > 0 {
            append(*sb, "*");
            n -= 1;
        }
        append(*sb, function.return_type);
        append(*sb, " #c_call;\n");
    }

    write_entire_file("function_pointers.jai", *sb);
}

output_enums :: () {
    sb: String_Builder;

    for e : vk_enums {
        append(*sb, e.name);
        append(*sb, " :: ");
        if e.alias.count > 0 {
            append(*sb, e.alias);
            append(*sb, ";\n\n");
        } else {
            append(*sb, "enum {\n");
            for m : e.members {
                append(*sb, "    ");
                if m.alias.count > 0 {
                    append(*sb, m.name);
                    append(*sb, " :: ");
                    append(*sb, m.alias);
                    append(*sb, ";");
                } else if m.value.count > 0 {
                    append(*sb, m.name);
                    append(*sb, " :: ");
                    append(*sb, m.value);
                    append(*sb, ";");
                } else {
                    append(*sb, "/* ");
                    append(*sb, m.name);
                    append(*sb, " */");
                }

                if m.comment.count > 0 {
                    append(*sb, " /*");
                    append(*sb, m.comment);
                    append(*sb, " */");
                }

                append(*sb, "\n");
            }
            append(*sb, "}\n\n");
        }
    }

    write_entire_file("enums.jai", *sb);
}

output_enum_flags :: () {
    sb: String_Builder;

    for e : vk_enum_flags {
        append(*sb, e.name);
        append(*sb, " :: enum_flags ");
        append(*sb, e.type);
        append(*sb, " {\n");

        for m : e.members {
            append(*sb, "    ");
            if m.value.count > 0 {
                append(*sb, m.name);
                append(*sb, " :: ");
                append(*sb, m.value);
                append(*sb, ";");
            } else if m.bitpos.count > 0 {
                append(*sb, m.name);
                append(*sb, " :: ");
                append(*sb, "1 << ");
                append(*sb, m.bitpos);
                append(*sb, ";");
            } else if m.alias.count > 0 {
                append(*sb, m.name);
                append(*sb, " :: ");
                append(*sb, m.alias);
                append(*sb, ";");
            } else {
                append(*sb, "/* ");
                append(*sb, m.name);
                append(*sb, " */");
            }

            append(*sb, "\n");
        }

        append(*sb, "}\n\n");
    }

    write_entire_file("enum_flags.jai", *sb);
}

output_constants :: () {
    sb: String_Builder;

    for c : vk_constants {
        using c;
        append(*sb, name);
        append(*sb, " : ");
        append(*sb, type);
        append(*sb, " : ");
        if flip {
            append(*sb, "~cast(");
            append(*sb, type);
            append(*sb, ")");
        }
        append(*sb, value);
        append(*sb, ";\n");
    }

    write_entire_file("constants.jai", *sb);
}

#import,file "../module.jai";
#import "Basic";
#import "String";
#import "Compiler";
#import "File";
