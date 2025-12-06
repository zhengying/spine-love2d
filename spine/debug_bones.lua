-- Spine Bone Transform Debug Utility
-- Prints detailed bone hierarchy and transform information for debugging

local debug_bones = {}

function debug_bones.printBoneHierarchy(skeleton)
    print("\n=== BONE HIERARCHY ===")
    for i, bone in ipairs(skeleton.bones) do
        local indent = ""
        local parent = bone.parent
        local depth = 0
        
        -- Calculate depth
        while parent do
            depth = depth + 1
            parent = parent.parent
        end
        
        for j = 1, depth do
            indent = indent .. "  "
        end
        
        print(string.format("%s[%d] %s (parent: %s)", 
            indent, i, bone.data.name, bone.parent and bone.parent.data.name or "none"))
    end
    print("==================\n")
end

function debug_bones.printBoneTransforms(skeleton, boneName)
    local bone = skeleton:findBone(boneName)
    if not bone then
        print("Bone not found: " .. boneName)
        return
    end
    
    print(string.format("\n=== BONE: %s ===", boneName))
    print("Local Transform:")
    print(string.format("  Position: (%.2f, %.2f)", bone.x, bone.y))
    print(string.format("  Rotation: %.2f°", bone.rotation))
    print(string.format("  Scale: (%.2f, %.2f)", bone.scaleX, bone.scaleY))
    print(string.format("  Shear: (%.2f, %.2f)", bone.shearX, bone.shearY))
    
    print("\nWorld Transform:")
    print(string.format("  Position: (%.2f, %.2f)", bone.worldX, bone.worldY))
    print(string.format("  Matrix: [%.3f, %.3f]", bone.a, bone.b))
    print(string.format("          [%.3f, %.3f]", bone.c, bone.d))
    
    if bone.parent then
        print(string.format("\nParent: %s", bone.parent.data.name))
        print(string.format("  World Position: (%.2f, %.2f)", bone.parent.worldX, bone.parent.worldY))
    end
    print("==================\n")
end

function debug_bones.printAllBoneTransforms(skeleton)
    print("\n=== ALL BONE TRANSFORMS ===")
    for i, bone in ipairs(skeleton.bones) do
        print(string.format("[%d] %s: world=(%.1f, %.1f) local=(%.1f, %.1f) rot=%.1f°", 
            i, bone.data.name, bone.worldX, bone.worldY, bone.x, bone.y, bone.rotation))
    end
    print("==================\n")
end

function debug_bones.printAttachmentInfo(skeleton, slotName)
    local slot = skeleton:findSlot(slotName)
    if not slot then
        print("Slot not found: " .. slotName)
        return
    end
    
    print(string.format("\n=== SLOT: %s ===", slotName))
    print(string.format("Bone: %s", slot.bone.data.name))
    print(string.format("Attachment: %s", slot.attachment and slot.attachment.name or "none"))
    
    if slot.attachment then
        local att = slot.attachment
        print(string.format("\nAttachment Type: %s", att.type))
        
        if att.type == "region" then
            print(string.format("  Position: (%.2f, %.2f)", att.x or 0, att.y or 0))
            print(string.format("  Rotation: %.2f°", att.rotation or 0))
            print(string.format("  Scale: (%.2f, %.2f)", att.scaleX or 1, att.scaleY or 1))
            print(string.format("  Size: %.2f × %.2f", att.width, att.height))
            
            if att.offset and #att.offset >= 8 then
                print("\n  Local Vertices (offset):")
                print(string.format("    BL: (%.2f, %.2f)", att.offset[1], att.offset[2]))
                print(string.format("    BR: (%.2f, %.2f)", att.offset[3], att.offset[4]))
                print(string.format("    TR: (%.2f, %.2f)", att.offset[5], att.offset[6]))
                print(string.format("    TL: (%.2f, %.2f)", att.offset[7], att.offset[8]))
            end
            
            -- Compute and show world vertices
            local worldVertices = {}
            att:computeWorldVertices(slot.bone, worldVertices)
            if #worldVertices >= 16 then
                print("\n  World Vertices:")
                print(string.format("    V1: (%.2f, %.2f) UV:(%.3f, %.3f)", 
                    worldVertices[1], worldVertices[2], worldVertices[3], worldVertices[4]))
                print(string.format("    V2: (%.2f, %.2f) UV:(%.3f, %.3f)", 
                    worldVertices[5], worldVertices[6], worldVertices[7], worldVertices[8]))
                print(string.format("    V3: (%.2f, %.2f) UV:(%.3f, %.3f)", 
                    worldVertices[9], worldVertices[10], worldVertices[11], worldVertices[12]))
                print(string.format("    V4: (%.2f, %.2f) UV:(%.3f, %.3f)", 
                    worldVertices[13], worldVertices[14], worldVertices[15], worldVertices[16]))
            end
        end
    end
    print("==================\n")
end

function debug_bones.compareWithExpected(bone, expectedWorldX, expectedWorldY)
    local diffX = bone.worldX - expectedWorldX
    local diffY = bone.worldY - expectedWorldY
    local distance = math.sqrt(diffX * diffX + diffY * diffY)
    
    print(string.format("\n=== COMPARISON: %s ===", bone.data.name))
    print(string.format("Expected: (%.2f, %.2f)", expectedWorldX, expectedWorldY))
    print(string.format("Actual:   (%.2f, %.2f)", bone.worldX, bone.worldY))
    print(string.format("Diff:     (%.2f, %.2f)", diffX, diffY))
    print(string.format("Distance: %.2f", distance))
    print("==================\n")
end

return debug_bones
