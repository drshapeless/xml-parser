VK_XML_PATH :: "vk.xml";

// Enabling dynamic loader will generate function pointers to all the
// functions and a some dynamic loader helper functions.
DYNAMIC_LOADER :: true;

// Setting STRIP_VULKAN_PREFIX to true will strip all the Vulkan
// related prefixes, e.g. Vk or vk.
STRIP_VULKAN_PREFIX :: false;

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
    output_function_pointers();
    output_enums();
    output_enum_flags();
    output_constants();
    if DYNAMIC_LOADER {
        output_dynamic_functions();
    } else {
        output_functions();
    }


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

// If the member is a standalone comment, the comment will be stored
// in name, alias and value will be empty string. This is bad design
// but whatever.
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

// Same as enum member, standalone comment is store in name.
VK_Enum_Flags_Member :: struct {
    name    : string;
    value   : string;
    bitpos  : string;
    alias   : string;
    comment : string;
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
            vk_member.comment = member_node.inner_string;
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
            member.comment = member_node.inner_string;
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
                    if member.name == "sType" && structure.name != "VkBaseInStructure" && structure.name != "VkBaseOutStructure" {
                        append(*sb, "    ");
                        append(*sb, member.name);
                        append(*sb, ": ");
                        append(*sb, member.type);
                        append(*sb, " = .");
                        append(*sb, get_sType_default_value_from_struct_name(structure.name));
                        append(*sb, ";\n");
                    } else {
                        output_structure_member(member, *sb);
                    }
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
                if m.name.count > 0 {
                    append(*sb, "    ");
                    append(*sb, strip_enum_member_name(m.name, e.name));
                    append(*sb, " :: ");
                    if m.alias.count > 0 {
                        // alias refers to some valid member, fix it also.
                        append(*sb, strip_enum_member_name(m.alias, e.name));
                        append(*sb, ";");
                    } else if m.value.count > 0 {
                        append(*sb, m.value);
                        append(*sb, ";");
                    }
                }

                if m.comment.count > 0 {
                    if m.name.count > 0 {
                        append(*sb, " /* ");
                        append(*sb, m.comment);
                        append(*sb, " */");
                    } else {
                        append(*sb, "/*\n");
                        append(*sb, m.comment);
                        append(*sb, "\n*/");
                    }
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
            if m.name.count > 0 {
                append(*sb, "    ");
                append(*sb, strip_enum_flag_bits(m.name, e.name));
                append(*sb, " :: ");
                if m.value.count > 0 {
                    append(*sb, m.value);
                    append(*sb, ";");
                } else if m.bitpos.count > 0 {
                    append(*sb, "1 << ");
                    append(*sb, m.bitpos);
                    append(*sb, ";");
                } else if m.alias.count > 0 {
                    append(*sb, strip_enum_flag_bits(m.alias, e.name));
                    append(*sb, ";");
                }
            }

            // There will not be a trailing comment after a enum_flags
            // member.
            if m.comment.count > 0 {
                append(*sb, "/*\n");
                append(*sb, m.comment);
                append(*sb, "\n*/");
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

output_dynamic_functions :: () {
    sb: String_Builder;
    sb0: String_Builder;

    device_func   : [..]string;
    instance_func : [..]string;
    global_func   : [..]string;

    for f : vk_functions {
        // This part generate function pointer.
        append(*sb, "PFN_");
        append(*sb, f.name);
        append(*sb, " :: ");
        if f.alias.count > 0 {
            append(*sb, f.alias);
            append(*sb, ";\n");
        } else {
            append(*sb, "#type (");
            output_function_params(f.params, *sb);
            append(*sb, ") -> ");
            write_pointers(f.number_of_pointer, *sb);
            append(*sb, f.return_type);
            append(*sb, " #c_call;\n");
        }

        // This part generate loader.
        append(*sb0, f.name);
        append(*sb0, " : PFN_");
        append(*sb0, f.name);
        append(*sb0, ";\n");

        // Check if the first param is VkDevice, VkInstance or VkPhysicalDevice
        if f.params.count > 0 {
            first_param_type := f.params[0].type;
            if first_param_type == {
            case "VkCommandBuffer";
                #through;
            case "VkQueue";
                #through;
            case "VkExternalComputeQueueNV";
                #through;
            case "VkDevice";
                if f.name == "vkGetDeviceProcAddr" {
                    // In Odin, they load this function twice in
                    // instance and device functions and I don't know
                    // why.
                    array_add(*instance_func, f.name);
                } else {
                    array_add(*device_func, f.name);
                }
            case "VkInstance";
                #through;
            case "VkPhysicalDevice";
                if f.name != "vkGetInstanceProcAddr" {
                    array_add(*instance_func, f.name);
                }
            case;
                array_add(*global_func, f.name);
            }
        }
    }

    append(*sb0, "\n");
    append(*sb0, "vk_load_global_functions :: (vk_get_instance_proc_addr: *void) {\n");
    append(*sb0, "    vkGetInstanceProcAddr = xx vk_get_instance_proc_addr;\n\n");
    align_pos := longest_string(global_func);
    for f : global_func {
        append(*sb0, "    ");
        append(*sb0, f);
        repeat_string(" ", align_pos - f.count, *sb0);
        append(*sb0, " = xx vkGetInstanceProcAddr(null, \"");
        append(*sb0, f);
        append(*sb0, "\");\n");
    }
    append(*sb0, "}\n\n");

    append(*sb0, "vk_load_instance_functions :: (instance: VkInstance) {\n");
    align_pos = longest_string(instance_func);
    for f : instance_func {
        append(*sb0, "    ");
        append(*sb0, f);
        repeat_string(" ", align_pos - f.count, *sb0);
        append(*sb0, " = xx vkGetInstanceProcAddr(instance, \"");
        append(*sb0, f);
        append(*sb0, "\");\n");
    }
    append(*sb0, "}\n\n");

    append(*sb0, "vk_load_device_functions :: (device: VkDevice) {\n");
    align_pos = longest_string(device_func);
    for f : device_func {
        append(*sb0, "    ");
        append(*sb0, f);
        repeat_string(" ", align_pos - f.count, *sb0);
        append(*sb0, " = xx vkGetDeviceProcAddr(device, \"");
        append(*sb0, f);
        append(*sb0, "\");\n");
    }
    append(*sb0, "}\n");

    // Maybe in the future I will just generate to functions.jai
    write_entire_file("dynamic_functions.jai", *sb);
    write_entire_file("dynamic_loader.jai", *sb0);
}

repeat_string :: (s: string, count: int, sb: *String_Builder) {
    n := count;
    while n > 0 {
        append(sb, s);
        n -= 1;
    }
}

write_pointers :: (count: int, sb: *String_Builder) {
    repeat_string("*", count, sb);
}

longest_string :: (ss: []string) -> int {
    n : int;
    for s : ss {
        if s.count > n {
            n = s.count;
        }
    }

    return n;
}

is_upper :: (byte: u8) -> bool {
    if byte >= #char "A" && byte <= #char "Z" return true;
    return false;
}

// This function is directly stolen from Vulkan binding in Jai,
// slightly modified for Vulkan 1.4 or later.
get_sType_default_value_from_struct_name :: (name: string) -> string {
    assert(name.count >= 3);

    is_num :: (byte: u8) -> bool {
        if byte >= #char "0" && byte <= #char "9" return true;
        return false;
    }

    builder: String_Builder;
    append(*builder, name[2]);
    for i:3..name.count-1 {
        if is_upper(name[i]) {
            is_first_uppercase := !is_upper(name[i-1]);
            is_end_of_uppercase_word := (i != name.count-1 && !is_upper(name[i+1]));
            is_bit_count := is_num(name[i-1]) && slice(name, i, 3) == "Bit";
            if (is_first_uppercase || is_end_of_uppercase_word) && !is_bit_count {
                append(*builder, #char "_");
            } else if (i >= 4 && slice(name, i-4, 4) == "AABB") { // Special case hack for names involing AABB
                append(*builder, #char "_");
            }
            append(*builder, name[i]);
        } else if is_num(name[i]) {
            if !is_num(name[i-1]) {
                append(*builder, #char "_");
            }
            append(*builder, name[i]);
        } else {
            append(*builder, to_upper(name[i]));
        }
    }

    type_string := builder_to_string(*builder);

    // This is a fucking mess because it makes too many stupid
    // allocations. Don't bother to fix it. But seems like replace()
    // does not allcate new memory if the target string is not found.
    type_string = replace(type_string, "PHYSICAL_DEVICE_VULKAN_1", "PHYSICAL_DEVICE_VULKAN_1_");
    type_string = replace(type_string, "_INT_64_", "_INT64_");
    type_string = replace(type_string, "_INT_8_", "_INT8_");
    type_string = replace(type_string, "_UINT_8_", "_UINT8_");
    type_string = replace(type_string, "_FLOAT_16_", "_FLOAT16_");
    type_string = replace(type_string, "_FLOAT_8_", "_FLOAT8_");
    type_string = replace(type_string, "_BFLOAT_16_", "_BFLOAT16_");
    type_string = replace(type_string, "_ASTCHDR_", "_ASTC_HDR_");
    type_string = replace(type_string, "_H_264_", "_H264_");
    type_string = replace(type_string, "_H_265_", "_H265_");
    type_string = replace(type_string, "_A_V_1_", "_AV1_");
    type_string = replace(type_string, "_V_P_9_", "_VP9_");
    type_string = replace(type_string, "_RGB_A_10_X_6_", "_RGBA10X6_");
    type_string = replace(type_string, "_2_D_", "_2D_");
    type_string = replace(type_string, "_3_D_", "_3D_");

    return type_string;
}

pascal_to_screaming_snake :: (s: string) -> string {
    is_beginning := true;

    sb: String_Builder;
    for c, index : s {
        if is_upper(c) {
            if is_beginning {
                is_beginning = false;
            } else if c == #char "V" && s[index - 1] == #char "A" {
                // do nothing
            } else {
                append(*sb, "_");
            }
            append(*sb, c);
        } else {
            append(*sb, to_upper(c));
        }
    }

    return builder_to_string(*sb);
}

VULKAN_SUFFIX :: string.[
"KHR",
"EXT",
"LUNARG",
"NV",
"AMD",
"INTEL",
"ARM",
"QCOM",
"FUCHSIA",
"MSFT",
"ANDROID",
];

check_vendor_suffix :: (s: string) -> string {
    for suf : VULKAN_SUFFIX {
        if ends_with(s, suf) {
            return suf;
        }
    }

    return "";
}

strip_enum_member_name :: (member_name: string, enum_name: string) -> string {
    name := member_name;
    ename := enum_name;

    // This can be implemented as builtin remove(), however I don't
    // want to allocate more memory.
    esuffix := check_vendor_suffix(enum_name);
    ename = remove_right(ename, esuffix);

    prefix := pascal_to_screaming_snake(ename);
    if enum_name == "VkResult" {
        // Hard code VkResult prefix, why? It sucks.
        prefix = "VK";
    }
    found := false;
    name, found = remove_left(name, prefix);

    // Remove leading _
    if found {
        name.data += 1;
        name.count -= 1;
    }

    suffix := check_vendor_suffix(name);
    name, found = remove_right(name, suffix);
    // Remove trailing _
    if found {
        name.count -= 1;
    }

    // Prefix a E in front of a digit beginning name.
    // This is ugly, I am thinking of a better way to deal with this.
    if is_digit(name[0]) {
        name = sprint("E%", name);
    }

    return name;
}

strip_enum_flag_bits :: (member_name: string, enum_name: string) -> string {
    // Vulkan flag bits suck, this is almost the identical copy of
    // strip_enum_member_name(), but with some extra rules. I am too
    // lazy to extract their common procedures.

    // For the enum type, it is suffixed with FlagBits, but for its
    // member, it is suffixed with BIT. And on top of that, the enum
    // is also suffixed with vendor names like NV.

    name := member_name;
    ename := enum_name;

    esuffix := check_vendor_suffix(enum_name);
    ename = remove_right(ename, esuffix);

    // There are some ridiculous naming like VkAccessFlagBits2 and its
    // member is VK_ACCESS_2_NONE, dealing with it.
    is_trailing_digit := false;
    if is_digit(enum_name[enum_name.count - 1]) {
        is_trailing_digit = true;
        ename.count -= 1;
    }

    ename = remove_right(ename, "FlagBits");

    found := false;
    prefix := pascal_to_screaming_snake(ename);
    if is_trailing_digit {
        prefix = tprint("%_%", prefix, slice(enum_name, enum_name.count - 1, 1));
    }
    name, found = remove_left(name, prefix);
    // Remove leading _
    if found {
        name.data += 1;
        name.count -= 1;
    }

    suffix := check_vendor_suffix(enum_name);
    name, found = remove_right(name, suffix);
    // Remove trailing _
    if found {
        name.count -= 1;
    }

    name = remove_right(name, "_BIT");

    if is_digit(name[0]) {
        name = sprint("E%", name);
    }

    reset_temporary_storage();
    return name;
}

// Remove the leading string, it does not allocate memory
remove_left :: (s: string, target: string) -> string, found:bool {
    if target.count > 0 && s.count >= target.count {
        sub := slice(s, 0, target.count);
        if sub == target {
            return slice(s, target.count, s.count - target.count), true;
        }
    }

    return s, false;
}


// Remove the trailing string, it does not allocate memory
remove_right :: (s: string, target: string) -> string, found:bool {
    if target.count > 0 && s.count >= target.count {
        sub := slice(s, s.count - target.count, target.count);
        if sub == target {
            return slice(s, 0, s.count - target.count), true;
        }
    }

    return s, false;
}

#import,file "../module.jai";
#import "Basic";
#import "String";
#import "Compiler";
#import "File";
