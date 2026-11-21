import Foundation
import SwiftUI

// MARK: - 六大能力

enum Ability: String, CaseIterable, Identifiable {
    case str = "力量"
    case dex = "敏捷"
    case con = "體質"
    case int = "智力"
    case wis = "感知"
    case cha = "魅力"

    var id: String { rawValue }

    var abbreviation: String {
        switch self {
        case .str: return "STR"
        case .dex: return "DEX"
        case .con: return "CON"
        case .int: return "INT"
        case .wis: return "WIS"
        case .cha: return "CHA"
        }
    }
}

// MARK: - 職業資料

enum DnDClass: String, CaseIterable, Identifiable, Codable {
    case barbarian = "野蠻人"
    case bard = "吟遊詩人"
    case cleric = "牧師"
    case druid = "德魯伊"
    case fighter = "戰士"
    case monk = "武僧"
    case paladin = "聖武士"
    case ranger = "遊俠"
    case rogue = "遊蕩者"
    case sorcerer = "術士"
    case warlock = "邪術師"
    case wizard = "法師"

    var id: String { rawValue }

    var hitDie: Int {
        switch self {
        case .barbarian: return 12
        case .fighter, .paladin, .ranger: return 10
        case .sorcerer, .wizard: return 6
        default: return 8
        }
    }

    var recommendation: (abilities: Set<Ability>, guidance: String) {
        switch self {
        case .barbarian:
            return ([.str, .con], "力量 STR 優先，接著是體質 CON。")
        case .bard:
            return ([.cha, .dex], "魅力 CHA 優先，接著是敏捷 DEX。")
        case .cleric:
            return ([.wis, .str, .con], "感知 WIS 優先，其次可選力量 STR 或體質 CON。")
        case .druid:
            return ([.wis, .con], "感知 WIS 優先，接著是體質 CON。")
        case .fighter:
            return ([.str, .dex, .con], "依武器選力量 STR 或敏捷 DEX 為主力，接著考慮體質 CON。")
        case .monk:
            return ([.dex, .wis], "敏捷 DEX 優先，接著是感知 WIS。")
        case .paladin:
            return ([.str, .cha], "力量 STR 優先，接著是魅力 CHA。")
        case .ranger:
            return ([.dex, .str, .wis], "依武器選敏捷 DEX 或力量 STR 為主力，接著考慮感知 WIS。")
        case .rogue:
            return ([.dex, .int, .cha], "敏捷 DEX 優先。若偏好法術可考慮智力 INT，偏好交涉則考慮魅力 CHA。")
        case .sorcerer, .warlock:
            return ([.cha, .con], "魅力 CHA 優先，接著是體質 CON。")
        case .wizard:
            return ([.int, .con, .dex], "智力 INT 優先，其次可選體質 CON 或敏捷 DEX。")
        }
    }

    var savingThrows: Set<Ability> {
        switch self {
        case .barbarian, .fighter: return [.str, .con]
        case .bard: return [.dex, .cha]
        case .rogue: return [.dex, .int]
        case .cleric, .paladin, .warlock: return [.wis, .cha]
        case .druid, .wizard: return [.int, .wis]
        case .monk, .ranger: return [.str, .dex]
        case .sorcerer: return [.con, .cha]
        }
    }
}

// MARK: - 角色卡與本機存檔

private struct SavedCharacter: Codable, Identifiable {
    let id: UUID
    let name: String
    let story: String
    let characterClass: DnDClass
    let scores: [Int]

    static let proficiencyBonus = 2

    var isValid: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && scores.count == Ability.allCases.count
            && scores.allSatisfy { (1...20).contains($0) }
    }

    func modifier(at index: Int) -> Int {
        Int(floor(Double(scores[index] - 10) / 2.0))
    }

    var maxHP: Int {
        let constitutionIndex = Ability.allCases.firstIndex(of: .con) ?? 2
        return max(1, characterClass.hitDie + modifier(at: constitutionIndex))
    }

    func savingThrow(at index: Int) -> Int {
        let proficient = characterClass.savingThrows.contains(Ability.allCases[index])
        return modifier(at: index) + (proficient ? Self.proficiencyBonus : 0)
    }
}

private func modifierText(_ value: Int) -> String {
    value >= 0 ? "+\(value)" : "\(value)"
}

private struct CharacterFile {
    let url: URL

    static func local() throws -> Self {
        let folder = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: false
        )
        return Self(url: folder.appendingPathComponent("DnD5e/characters-v1.json"))
    }

    func load() throws -> [SavedCharacter] {
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
            return []
        }

        let characters = try JSONDecoder().decode([SavedCharacter].self, from: data)
        guard characters.allSatisfy(\.isValid),
              Set(characters.map(\.id)).count == characters.count else {
            throw CocoaError(.fileReadCorruptFile)
        }
        return characters
    }

    func save(_ characters: [SavedCharacter]) throws {
        let data = try JSONEncoder().encode(characters)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: url, options: .atomic)
    }
}

// MARK: - 角色管理器

struct ContentView: View {
    @State private var characters: [SavedCharacter]?
    @State private var loadFailed = false
    @State private var showingCreator = false

    var body: some View {
        NavigationStack {
            Group {
                if let characters {
                    if characters.isEmpty {
                        Label("尚未建立角色", systemImage: "person.crop.rectangle")
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        List(characters) { character in
                            NavigationLink {
                                ScrollView {
                                    CharacterSheet(character: character)
                                        .frame(maxWidth: 600, alignment: .leading)
                                        .padding()
                                        .frame(maxWidth: .infinity)
                                }
                                .navigationTitle("角色卡")
                            } label: {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(character.name)
                                        .font(.headline)
                                    Text("Lv.1 · \(character.characterClass.rawValue) · HP \(character.maxHP)")
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                } else if loadFailed {
                    VStack(spacing: 12) {
                        Text("無法讀取本機角色存檔。")
                        Button("重新載入", action: loadCharacters)
                            .buttonStyle(.bordered)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ProgressView("載入角色…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .safeAreaInset(edge: .bottom) {
                Button {
                    showingCreator = true
                } label: {
                    Label("建立新角色", systemImage: "plus")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 5)
                }
                .buttonStyle(.borderedProminent)
                .disabled(characters == nil)
                .padding()
                .frame(maxWidth: .infinity)
                .background(.regularMaterial)
            }
            .navigationTitle("DND角色管理器")
        }
        .task {
            if characters == nil && !loadFailed { loadCharacters() }
        }
        .sheet(isPresented: $showingCreator) {
            CharacterCreator(onSave: saveCharacter)
        }
    }

    private func loadCharacters() {
        do {
            characters = try CharacterFile.local().load()
            loadFailed = false
        } catch {
            loadFailed = true
        }
    }

    private func saveCharacter(_ character: SavedCharacter) throws {
        let file = try CharacterFile.local()
        var updated = try file.load()
        guard !updated.contains(where: { $0.id == character.id }) else {
            characters = updated
            return
        }
        updated.insert(character, at: 0)
        try file.save(updated)
        characters = updated
    }
}

// MARK: - 擲骰資料

struct DiceRoll: Identifiable {
    let id = UUID()
    let dice: [Int]

    var droppedIndex: Int? {
        guard let lowest = dice.min() else { return nil }
        return dice.firstIndex(of: lowest)
    }

    var score: Int {
        dice.reduce(0, +) - (dice.min() ?? 0)
    }

    static func generate() -> DiceRoll {
        DiceRoll(
            dice: (0..<4).map { _ in
                Int.random(in: 1...6)
            }
        )
    }
}

private struct AbilityRolls {
    private(set) var rolls: [DiceRoll] = []
    private(set) var assignments: [Ability: Int] = [:]
    private(set) var selectedIndex: Int?

    func assignedAbility(for index: Int) -> Ability? {
        assignments.first { $0.value == index }?.key
    }

    mutating func select(_ index: Int) {
        guard rolls.indices.contains(index), assignedAbility(for: index) == nil else { return }
        selectedIndex = selectedIndex == index ? nil : index
    }

    mutating func assign(to ability: Ability) {
        guard let index = selectedIndex, assignedAbility(for: index) == nil else { return }
        assignments[ability] = index
        selectedIndex = nil
    }

    mutating func unassign(_ ability: Ability) {
        assignments.removeValue(forKey: ability)
    }

    mutating func cancelSelection() {
        selectedIndex = nil
    }

    mutating func clear() {
        assignments.removeAll()
        cancelSelection()
    }

    mutating func reroll() {
        rolls = (0..<6).map { _ in DiceRoll.generate() }
        clear()
    }
}

private enum RollReveal: Equatable {
    case idle
    case dice(Int)
    case droppingLowest
    case showingTotals
    case finished

    var visibleDice: Int {
        switch self {
        case .idle: return 0
        case .dice(let count): return count
        case .droppingLowest, .showingTotals, .finished: return 4
        }
    }

    var showsLowest: Bool {
        self == .droppingLowest || showsTotals
    }

    var showsTotals: Bool {
        self == .showingTotals || self == .finished
    }

    var isRolling: Bool {
        self != .idle && self != .finished
    }
}

private struct AssignmentFeedback: Identifiable {
    let id = UUID()
    let ability: Ability
}

// MARK: - 角色創建主畫面

private struct CharacterCreator: View {
    let onSave: (SavedCharacter) throws -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var rollReveal = RollReveal.idle
    @State private var assignmentFeedback: AssignmentFeedback?

    @State private var step = 0
    @State private var characterID = UUID()

    @State private var characterName = ""
    @State private var characterStory = ""
    @State private var selectedClass: DnDClass = .fighter

    @State private var manualMode = false
    @State private var abilityRolls = AbilityRolls()
    @State private var manualScores =
        Array(repeating: "10", count: 6)

    @State private var showSaveError = false
    @State private var showDiscardAlert = false
    @State private var showRerollAlert = false

    private let stepNames = [
        "基本資料",
        "選擇職業",
        "能力值分配",
        "數值確認",
        "完成角色卡"
    ]

    // MARK: - 計算邏輯

    private func score(for index: Int) -> Int {
        if manualMode {
            return manualScore(at: index) ?? 0
        }

        let ability = Ability.allCases[index]
        guard let rollIndex = abilityRolls.assignments[ability] else { return 0 }
        return abilityRolls.rolls[rollIndex].score
    }

    private var draftCard: SavedCharacter {
        SavedCharacter(
            id: characterID,
            name: characterName.trimmingCharacters(in: .whitespacesAndNewlines),
            story: characterStory.trimmingCharacters(in: .whitespacesAndNewlines),
            characterClass: selectedClass,
            scores: Ability.allCases.indices.map { score(for: $0) }
        )
    }

    private func manualScore(at index: Int) -> Int? {
        let text = manualScores[index].trimmingCharacters(in: .whitespacesAndNewlines)
        guard let value = Int(text), (1...20).contains(value) else { return nil }
        return value
    }

    private var abilitiesValid: Bool {
        if manualMode {
            return manualScores.indices.allSatisfy { manualScore(at: $0) != nil }
        }

        return rollReveal == .finished
            && abilityRolls.assignments.count == Ability.allCases.count
    }

    private var canContinue: Bool {
        switch step {
        case 0:
            return !characterName
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .isEmpty
        case 2:
            return abilitiesValid
        default:
            return true
        }
    }

    // MARK: - 主畫面

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("建立角色")
                        .font(.title2.bold())
                    Spacer()
                    Button("取消") {
                        showDiscardAlert = true
                    }
                }
                .alert("放棄建立角色？", isPresented: $showDiscardAlert) {
                    Button("繼續編輯", role: .cancel) {}
                    Button("放棄", role: .destructive) { dismiss() }
                }

                Text("步驟 \(step + 1) / 5 · \(stepNames[step])")
                    .foregroundStyle(.secondary)

                ProgressView(value: Double(step + 1), total: 5)
            }
            .padding()

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    switch step {
                    case 0: identityStep
                    case 1: classStep
                    case 2: abilityStep
                    case 3: calculationStep
                    default: CharacterSheet(character: draftCard)
                    }
                }
                .frame(maxWidth: 600, alignment: .leading)
                .padding()
            }

            Divider()

            HStack {
                Button("上一步") {
                    if step > 0 {
                        abilityRolls.cancelSelection()
                        assignmentFeedback = nil
                        step -= 1
                    }
                }
                .disabled(step == 0 || rollReveal.isRolling)

                Spacer()

                Button(step == 4 ? "儲存角色" : "下一步") {
                    if step == 4 {
                        do {
                            try onSave(draftCard)
                            dismiss()
                        } catch {
                            showSaveError = true
                        }
                    } else if canContinue {
                        step += 1
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(!canContinue)
            }
            .padding()
        }
        .interactiveDismissDisabled()
        .alert("無法儲存角色", isPresented: $showSaveError) {
            Button("確定", role: .cancel) {}
        } message: {
            Text("目前的角色資料仍在創角畫面。請再試一次。")
        }
    }

    // MARK: - 第一步：基本資料

    private var identityStep: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("建立你的冒險者")
                .font(.title.bold())

            TextField("角色姓名", text: $characterName)
                .textFieldStyle(.roundedBorder)

            Text("角色背景（選填）")
                .font(.headline)

            TextEditor(text: $characterStory)
                .frame(height: 140)
                .padding(4)
                .overlay {
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(.gray.opacity(0.4))
                }

            Label("此版本固定為 1 級角色", systemImage: "info.circle")
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - 第二步：選擇職業

    private var classStep: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("選擇職業")
                .font(.title.bold())

            Picker("職業", selection: $selectedClass) {
                ForEach(DnDClass.allCases) { characterClass in
                    Text(characterClass.rawValue)
                        .tag(characterClass)
                }
            }
            .pickerStyle(.menu)

            GroupBox("職業資訊") {
                VStack(alignment: .leading, spacing: 12) {
                    infoRow("職業", selectedClass.rawValue)
                    infoRow("生命骰", "1d\(selectedClass.hitDie)")
                    infoRow(
                        "豁免熟練",
                        Ability.allCases
                            .filter { selectedClass.savingThrows.contains($0) }
                            .map(\.rawValue)
                            .joined(separator: "、")
                    )
                    infoRow("熟練加值", modifierText(SavedCharacter.proficiencyBonus))
                }
                .frame(maxWidth: .infinity)
            }

            classRecommendation
        }
    }

    // MARK: - 第三步：能力值
    private var abilityStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("分配六大能力值")
                .font(.title.bold())

            classRecommendation

            Toggle("手動輸入能力值", isOn: Binding(
                get: { manualMode },
                set: { enabled in
                    manualMode = enabled
                    abilityRolls.cancelSelection()
                    assignmentFeedback = nil
                }
            ))
            .disabled(rollReveal.isRolling)

            if manualMode {
                manualAbilityFields
            } else {
                rollAssignmentCards
            }

            if !abilitiesValid && (manualMode || rollReveal == .finished) {
                Label(
                    "請完成所有能力值設定才能繼續",
                    systemImage: "exclamationmark.circle"
                )
                .foregroundStyle(.orange)
            }
        }
        .alert("重新擲骰？", isPresented: $showRerollAlert) {
            Button("取消", role: .cancel) {}
            Button("重新擲骰", role: .destructive) {
                startRolling()
            }
        } message: {
            Text("將替換全部六組骰值，並清除目前的分配。")
        }
    }

    private var classRecommendation: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 6) {
                Label("\(selectedClass.rawValue)的能力值建議", systemImage: "star")
                    .font(.headline)
                Text(selectedClass.recommendation.guidance)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var manualAbilityFields: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("請輸入 1～20 的整數。")
                .foregroundStyle(.secondary)

            ForEach(Ability.allCases.indices, id: \.self) { index in
                let ability = Ability.allCases[index]
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("\(ability.rawValue) \(ability.abbreviation)")
                        if selectedClass.recommendation.abilities.contains(ability) {
                            Label("建議", systemImage: "star")
                                .font(.caption)
                                .foregroundStyle(Color.accentColor)
                        }
                    }
                    Spacer()
                    TextField("能力值", text: $manualScores[index])
                        #if os(iOS)
                        .keyboardType(.numberPad)
                        #endif
                        .multilineTextAlignment(.trailing)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 100)
                        .accessibilityLabel(Text("\(ability.rawValue)能力值"))
                }
            }
        }
    }

    private var rollAssignmentCards: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("擲六組 4d6，每組捨去一顆最低骰。")
                .foregroundStyle(.secondary)

            ViewThatFits(in: .horizontal) {
                HStack { rollActions }
                VStack(alignment: .leading) { rollActions }
            }

            if rollReveal != .idle {
                Text(rollStatus)
                    .font(.headline)

                LazyVGrid(columns: cardColumns, spacing: 10) {
                    ForEach(abilityRolls.rolls.indices, id: \.self) { index in
                        rollCard(at: index)
                    }
                }
            }

            if rollReveal == .finished {
                Divider()

                Text("已分配 \(abilityRolls.assignments.count) / 6")
                    .font(.headline)
                if let index = abilityRolls.selectedIndex {
                    Text("已選第 \(index + 1) 組。點選能力卡即可分配或替換。")
                } else if let ability = assignmentFeedback?.ability {
                    Text("已分配給\(ability.rawValue) \(ability.abbreviation)。")
                } else if !abilitiesValid {
                    Text("先點選可分配的骰值卡，再點選能力卡。")
                }

                LazyVGrid(columns: cardColumns, spacing: 10) {
                    ForEach(Ability.allCases) { ability in
                        abilityCard(for: ability)
                    }
                }
            }
        }
        .task(id: abilityRolls.rolls.first?.id) {
            guard rollReveal.isRolling else { return }
            await revealRolls()
        }
        .task(id: assignmentFeedback?.id) {
            guard assignmentFeedback != nil else { return }
            do {
                try await Task.sleep(for: .milliseconds(700))
                guard !Task.isCancelled else { return }
                withAnimation(feedbackAnimation) { assignmentFeedback = nil }
            } catch {
                // 新的分配或離開畫面時，停止舊的高亮計時。
            }
        }
    }

    private var rollStatus: String {
        switch rollReveal {
        case .idle, .dice(0): return "準備擲骰…"
        case .dice(let count): return "揭曉第 \(count) 顆骰子 / 4"
        case .droppingLowest: return "劃掉每組最低的一顆骰子"
        case .showingTotals: return "加總剩下的三顆骰子"
        case .finished: return "六組骰值"
        }
    }

    private var feedbackAnimation: Animation? {
        reduceMotion ? nil : .easeOut(duration: 0.2)
    }

    private func startRolling() {
        guard !rollReveal.isRolling else { return }
        assignmentFeedback = nil
        abilityRolls.reroll()
        rollReveal = reduceMotion ? .finished : .dice(0)
    }

    @MainActor
    private func revealRolls() async {
        do {
            for count in 1...4 {
                try await reveal(.dice(count), after: 240)
            }
            try await reveal(.droppingLowest, after: 300)
            try await reveal(.showingTotals, after: 420)
            try await reveal(.finished, after: 240)
        } catch {
            // 畫面消失時，SwiftUI 會取消揭曉動畫。
        }
    }

    @MainActor
    private func reveal(_ phase: RollReveal, after milliseconds: Int) async throws {
        try await Task.sleep(for: .milliseconds(milliseconds))
        try Task.checkCancellation()
        withAnimation(feedbackAnimation) { rollReveal = phase }
    }

    private var cardColumns: [GridItem] {
        [GridItem(.adaptive(minimum: 105), spacing: 10, alignment: .top)]
    }

    @ViewBuilder
    private var rollActions: some View {
        if rollReveal == .idle {
            Button(action: startRolling) {
                Label("擲骰", systemImage: "dice")
            }
            .buttonStyle(.borderedProminent)
        } else {
            Button {
                showRerollAlert = true
            } label: {
                Label(rollReveal.isRolling ? "擲骰中…" : "重新擲骰", systemImage: "dice")
            }
            .buttonStyle(.bordered)
            .disabled(rollReveal.isRolling)

            if rollReveal == .finished {
                Button("清除分配") {
                    withAnimation(feedbackAnimation) {
                        abilityRolls.clear()
                        assignmentFeedback = nil
                    }
                }
                .buttonStyle(.bordered)
                .disabled(abilityRolls.assignments.isEmpty && abilityRolls.selectedIndex == nil)
            }
        }
    }

    private func rollCard(at index: Int) -> some View {
        let roll = abilityRolls.rolls[index]
        let assigned = abilityRolls.assignedAbility(for: index)
        let selected = abilityRolls.selectedIndex == index
        let status = assigned.map { "已分配 \($0.abbreviation)" }
            ?? (selected ? "已選取" : "可分配")
        let dropped = rollReveal.showsLowest ? roll.droppedIndex : nil
        let ready = rollReveal == .finished

        return Button {
            withAnimation(feedbackAnimation) {
                abilityRolls.select(index)
            }
        } label: {
            VStack(spacing: 7) {
                Text("第 \(index + 1) 組")
                    .font(.caption)

                HStack(spacing: 3) {
                    ForEach(roll.dice.indices, id: \.self) { dieIndex in
                        dieFace(
                            roll.dice[dieIndex],
                            isVisible: dieIndex < rollReveal.visibleDice,
                            isDropped: dieIndex == dropped
                        )
                    }
                }

                ZStack {
                    Text("—")
                        .foregroundStyle(.secondary)
                        .opacity(rollReveal.showsTotals ? 0 : 1)

                    if rollReveal.showsTotals {
                        Text("\(roll.score)")
                            .transition(.scale(scale: 0.8).combined(with: .opacity))
                    }
                }
                .font(.title2.bold().monospacedDigit())

                Text(ready ? status : "揭曉中")
                    .font(.caption)
            }
            .padding(8)
            .frame(maxWidth: .infinity)
            .background(
                selected ? Color.accentColor.opacity(0.16) : Color.gray.opacity(0.12),
                in: RoundedRectangle(cornerRadius: 12)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(Color.accentColor, lineWidth: 2)
                    .opacity(selected ? 1 : 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!ready || assigned != nil)
        .accessibilityLabel(Text(ready
            ? "第 \(index + 1) 組，能力值 \(roll.score)，\(status)"
            : "第 \(index + 1) 組，揭曉中"))
        .accessibilityHint(Text(ready && assigned == nil ? "再次點選可取消選取" : ""))
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func dieFace(_ value: Int, isVisible: Bool, isDropped: Bool) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 4)
                .strokeBorder(Color.secondary.opacity(0.3))
                .opacity(isVisible ? 0 : 1)

            if isVisible {
                Image(systemName: "die.face.\(value).fill")
                    .resizable()
                    .scaledToFit()
                    .foregroundStyle(Color.primary.opacity(isDropped ? 0.38 : 1))
                    .transition(.scale(scale: 0.55).combined(with: .opacity))
            }

            Capsule()
                .fill(Color.red)
                .frame(width: 19, height: 2)
                .rotationEffect(.degrees(-40))
                .scaleEffect(x: isDropped ? 1 : 0)
                .opacity(isDropped ? 1 : 0)
        }
        .frame(width: 17, height: 17)
        .accessibilityHidden(true)
    }

    private func abilityCard(for ability: Ability) -> some View {
        let index = abilityRolls.assignments[ability]
        let value = index.map { String(abilityRolls.rolls[$0].score) } ?? "—"
        let source = index.map { "第 \($0 + 1) 組" } ?? "未分配"
        let canAssign = abilityRolls.selectedIndex != nil
        let highlighted = assignmentFeedback?.ability == ability
        let recommended = selectedClass.recommendation.abilities.contains(ability)

        return VStack(spacing: 0) {
            Button {
                guard canAssign else { return }
                withAnimation(feedbackAnimation) {
                    abilityRolls.assign(to: ability)
                    assignmentFeedback = AssignmentFeedback(ability: ability)
                }
            } label: {
                VStack(spacing: 5) {
                    Text("\(ability.abbreviation) \(ability.rawValue)")
                        .font(.caption.bold())
                    if recommended {
                        Label("建議", systemImage: "star")
                            .font(.caption2)
                            .foregroundStyle(Color.accentColor)
                    }
                    Text(value)
                        .font(.title2.bold().monospacedDigit())
                    Text(source)
                        .font(.caption)
                }
                .padding(8)
                .frame(maxWidth: .infinity)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(canAssign ? Color.accentColor : Color.primary)
            .disabled(!canAssign)
            .accessibilityLabel(Text(recommended
                ? "\(ability.rawValue)，職業建議，\(source)，\(value)"
                : "\(ability.rawValue)，\(source)，\(value)"))

            if index != nil {
                Divider()
                Button {
                    withAnimation(feedbackAnimation) {
                        abilityRolls.unassign(ability)
                        if highlighted { assignmentFeedback = nil }
                    }
                } label: {
                    Text("取消分配")
                        .font(.caption)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.accentColor)
                .accessibilityLabel(Text("取消\(ability.rawValue)的分配"))
            }
        }
        .background(
            highlighted ? Color.accentColor.opacity(0.22) : Color.gray.opacity(0.12),
            in: RoundedRectangle(cornerRadius: 12)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(Color.accentColor, lineWidth: 2)
                .opacity(highlighted ? 1 : 0)
                .allowsHitTesting(false)
        }
        .scaleEffect(highlighted && !reduceMotion ? 1.04 : 1)
    }

    // MARK: - 第四步：計算結果

    private var calculationStep: some View {
        let character = draftCard
        return VStack(alignment: .leading, spacing: 18) {
            Text("角色數值確認")
                .font(.title.bold())

            GroupBox("基本戰鬥數值") {
                VStack(spacing: 12) {
                    infoRow("職業", selectedClass.rawValue)
                    infoRow("生命骰", "1d\(selectedClass.hitDie)")
                    infoRow("最大生命值", "\(character.maxHP)")
                    infoRow("熟練加值", modifierText(SavedCharacter.proficiencyBonus))
                }
            }

            Text("能力值與調整值")
                .font(.headline)

            ForEach(0..<6, id: \.self) { index in
                HStack {
                    Text(Ability.allCases[index].rawValue)
                    Spacer()
                    Text("\(character.scores[index])")
                    Text(modifierText(character.modifier(at: index)))
                        .frame(width: 50, alignment: .trailing)
                        .bold()
                }
            }

            Divider()

            Text("豁免加值")
                .font(.headline)

            SavingThrowRows(character: character)

            Text("✓ 表示職業提供的豁免熟練，已包含 +2 熟練加值。")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private func infoRow(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(value)
                .bold()
        }
    }

}

// MARK: - 共用角色卡

private struct CharacterSheet: View {
    let character: SavedCharacter

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(character.name)
                .font(.largeTitle.bold())

            Text("Lv.1 · \(character.characterClass.rawValue)")
                .font(.title3)
                .foregroundStyle(.secondary)

            HStack {
                statCard("HP", "\(character.maxHP)")
                statCard("生命骰", "1d\(character.characterClass.hitDie)")
                statCard("熟練", modifierText(SavedCharacter.proficiencyBonus))
            }

            Text("六大能力")
                .font(.headline)

            LazyVGrid(
                columns: Array(
                    repeating: GridItem(.flexible()),
                    count: 3
                ),
                spacing: 12
            ) {
                ForEach(0..<6, id: \.self) { index in
                    VStack(spacing: 6) {
                        Text(Ability.allCases[index].abbreviation)
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        Text(modifierText(character.modifier(at: index)))
                            .font(.title2.bold())

                        Text("\(character.scores[index])")
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(
                        Color.gray.opacity(0.1),
                        in: RoundedRectangle(cornerRadius: 12)
                    )
                }
            }

            Text("豁免加值")
                .font(.headline)

            SavingThrowRows(character: character)

            if !character.story.isEmpty {
                Divider()

                Text("角色背景")
                    .font(.headline)

                Text(character.story)
            }
        }
    }

    private func statCard(_ title: String, _ value: String) -> some View {
        VStack(spacing: 8) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)

            Text(value)
                .font(.title2.bold())
                .minimumScaleFactor(0.7)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(
            Color.gray.opacity(0.1),
            in: RoundedRectangle(cornerRadius: 12)
        )
    }
}

private struct SavingThrowRows: View {
    let character: SavedCharacter

    var body: some View {
        VStack(spacing: 10) {
            ForEach(0..<6, id: \.self) { index in
                let ability = Ability.allCases[index]
                let proficient =
                    character.characterClass.savingThrows.contains(ability)

                HStack {
                    Image(
                        systemName: proficient
                            ? "checkmark.circle.fill"
                            : "circle"
                    )
                    .foregroundStyle(
                        proficient ? Color.green : Color.gray
                    )

                    Text(ability.rawValue)

                    Spacer()

                    Text(modifierText(character.savingThrow(at: index)))
                        .bold()
                }
            }
        }
    }

}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
