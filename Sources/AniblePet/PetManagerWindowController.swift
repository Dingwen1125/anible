import AppKit

struct PetProfile {
    let id: String
    let name: String
    let portraitSet: PetPortraitSet?

    var isDefault: Bool {
        portraitSet == nil
    }

    static let defaultPet = PetProfile(id: "default", name: "默认宠物", portraitSet: nil)
}

final class PetManagerWindowController: NSWindowController {
    private var profiles: [PetProfile]
    private let onProfileSelected: (PetProfile) -> Void
    private let popup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let statusLabel = NSTextField(labelWithString: "当前使用：默认宠物")

    init(profiles: [PetProfile] = PetProfileStore.loadProfiles(), onProfileSelected: @escaping (PetProfile) -> Void) {
        self.profiles = profiles
        self.onProfileSelected = onProfileSelected

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 460, height: 320),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.minSize = NSSize(width: 420, height: 300)
        window.title = "Anible 宠物管理"
        window.center()

        super.init(window: window)
        buildInterface()
        refreshProfiles()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func buildInterface() {
        guard let contentView = window?.contentView else { return }

        let titleLabel = NSTextField(labelWithString: "我的桌面宠物")
        titleLabel.font = .boldSystemFont(ofSize: 22)

        let helperLabel = NSTextField(labelWithString: "上传新的宠物并命名，或者切换回默认宠物。")
        helperLabel.textColor = .secondaryLabelColor

        let chooseLabel = NSTextField(labelWithString: "当前宠物")

        let applyButton = NSButton(title: "使用选中宠物", target: self, action: #selector(applySelectedProfile))
        applyButton.bezelStyle = .rounded

        let uploadButton = NSButton(title: "上传新宠物", target: self, action: #selector(uploadNewPet))
        uploadButton.bezelStyle = .rounded

        let defaultButton = NSButton(title: "改用默认宠物", target: self, action: #selector(useDefaultPet))
        defaultButton.bezelStyle = .rounded

        let deleteButton = NSButton(title: "删除选中宠物", target: self, action: #selector(deleteSelectedPet))
        deleteButton.bezelStyle = .rounded

        let stack = NSStackView(views: [
            titleLabel,
            helperLabel,
            chooseLabel,
            popup,
            applyButton,
            uploadButton,
            defaultButton,
            deleteButton,
            statusLabel
        ])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(stack)

        popup.widthAnchor.constraint(equalToConstant: 260).isActive = true
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: contentView.trailingAnchor, constant: -24),
            stack.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 22),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: contentView.bottomAnchor, constant: -22)
        ])
    }

    private func refreshProfiles(selecting index: Int = 0) {
        popup.removeAllItems()
        popup.addItems(withTitles: profiles.map(\.name))
        popup.selectItem(at: min(max(index, 0), profiles.count - 1))
    }

    @objc private func applySelectedProfile() {
        let index = popup.indexOfSelectedItem
        guard profiles.indices.contains(index) else { return }
        let profile = profiles[index]
        onProfileSelected(profile)
        statusLabel.stringValue = "当前使用：\(profile.name)"
    }

    @objc private func uploadNewPet() {
        guard let petName = askForPetName() else { return }

        do {
            let portraitSet = try PetPortraitUploadWizard.run()
            let profile = try PetProfileStore.saveNewProfile(name: petName, portraitSet: portraitSet)
            profiles.append(profile)
            refreshProfiles(selecting: profiles.count - 1)
            onProfileSelected(profile)
            statusLabel.stringValue = "当前使用：\(profile.name)"
        } catch {
            let alert = NSAlert()
            alert.alertStyle = .warning
            alert.messageText = "画像上传未完成"
            alert.informativeText = error.localizedDescription
            alert.runModal()
        }
    }

    @objc private func useDefaultPet() {
        refreshProfiles(selecting: 0)
        onProfileSelected(.defaultPet)
        statusLabel.stringValue = "当前使用：默认宠物"
    }

    @objc private func deleteSelectedPet() {
        let index = popup.indexOfSelectedItem
        guard profiles.indices.contains(index) else { return }
        let profile = profiles[index]

        guard !profile.isDefault else {
            let alert = NSAlert()
            alert.messageText = "默认宠物不能删除"
            alert.informativeText = "你可以上传新的宠物，或者继续使用默认宠物。"
            alert.runModal()
            return
        }

        let confirm = NSAlert()
        confirm.alertStyle = .warning
        confirm.messageText = "删除「\(profile.name)」？"
        confirm.informativeText = "删除后这个上传的宠物形象会从本机移除。"
        confirm.addButton(withTitle: "删除")
        confirm.addButton(withTitle: "取消")
        guard confirm.runModal() == .alertFirstButtonReturn else { return }

        do {
            try PetProfileStore.deleteProfile(profile)
            profiles.remove(at: index)
            refreshProfiles(selecting: 0)
            onProfileSelected(.defaultPet)
            statusLabel.stringValue = "当前使用：默认宠物"
        } catch {
            let alert = NSAlert()
            alert.alertStyle = .warning
            alert.messageText = "删除失败"
            alert.informativeText = error.localizedDescription
            alert.runModal()
        }
    }

    private func askForPetName() -> String? {
        let alert = NSAlert()
        alert.messageText = "给新宠物取名"
        alert.informativeText = "这个名字会显示在宠物管理界面里。"
        alert.addButton(withTitle: "继续上传")
        alert.addButton(withTitle: "取消")

        let input = NSTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
        input.placeholderString = "例如：小橘"
        alert.accessoryView = input

        guard alert.runModal() == .alertFirstButtonReturn else { return nil }
        let name = input.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? "未命名宠物" : name
    }
}
