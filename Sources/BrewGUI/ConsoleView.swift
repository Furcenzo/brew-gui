// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Furcenzo

import SwiftUI

/// Panel na spodku okna – stav poslednej operácie a rozbaliteľný výstup.
struct ConsoleView: View {
    @Environment(AppModel.self) private var model
    @State private var selectedJobID: UUID?

    var body: some View {
        if let job = selectedJob {
            VStack(spacing: 0) {
                Divider()
                header(job)
                if model.consoleExpanded {
                    Divider()
                    output(job)
                        .frame(height: 220)
                }
            }
            .background(Color(nsColor: .windowBackgroundColor))
        }
    }

    private var selectedJob: Job? {
        if let selectedJobID, let job = model.jobs.first(where: { $0.id == selectedJobID }) { return job }
        return model.currentJob
    }

    private func header(_ job: Job) -> some View {
        HStack(spacing: 8) {
            stateIcon(job)
            Text(job.title).fontWeight(.medium)
            Text(job.lastLine)
                .font(.callout.monospaced())
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer()
            if model.jobs.count > 1 {
                Menu {
                    ForEach(model.jobs.reversed()) { item in
                        Button(item.title + " – " + item.started.formatted(date: .omitted, time: .shortened)) {
                            selectedJobID = item.id
                            model.consoleExpanded = true
                        }
                    }
                    Divider()
                    Button("Clear Finished") {
                        selectedJobID = nil
                        model.clearFinishedJobs()
                    }
                } label: {
                    Image(systemName: "clock.arrow.circlepath")
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .help("Operation History")
            }
            if job.isRunning {
                Button("Stop") { model.cancel(job) }
                    .controlSize(.small)
            }
            Button {
                withAnimation(.snappy(duration: 0.2)) { model.consoleExpanded.toggle() }
            } label: {
                Image(systemName: model.consoleExpanded ? "chevron.down" : "chevron.up")
            }
            .buttonStyle(.borderless)
            .help(model.consoleExpanded ? "Hide output (⌘J)" : "Show output (⌘J)")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { model.consoleExpanded.toggle() }
        .onChange(of: model.currentJob?.id) { selectedJobID = nil }
    }

    @ViewBuilder private func stateIcon(_ job: Job) -> some View {
        switch job.state {
        case .running: ProgressView().controlSize(.small)
        case .succeeded: Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
        case .failed(let code): Image(systemName: "xmark.octagon.fill").foregroundStyle(.red).help("Exit code \(code)")
        case .cancelled: Image(systemName: "stop.circle.fill").foregroundStyle(.secondary)
        }
    }

    private func output(_ job: Job) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 1) {
                    ForEach(Array(job.lines.enumerated()), id: \.offset) { index, line in
                        Text(line)
                            .font(.system(.callout, design: .monospaced))
                            .foregroundStyle(lineColor(line))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .id(index)
                    }
                }
                .textSelection(.enabled)
                .padding(10)
            }
            .background(Color(nsColor: .textBackgroundColor))
            .onChange(of: job.lines.count) { _, count in
                proxy.scrollTo(count - 1, anchor: .bottom)
            }
            .onAppear { proxy.scrollTo(job.lines.count - 1, anchor: .bottom) }
            .contextMenu {
                Button("Copy All Output") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(job.lines.joined(separator: "\n"), forType: .string)
                }
            }
        }
    }

    private func lineColor(_ line: String) -> Color {
        if line.hasPrefix("$ ") { return .accentColor }
        if line.hasPrefix("Error") || line.hasPrefix("Chyba") { return .red }
        if line.hasPrefix("Warning") { return .orange }
        if line.hasPrefix("==>") { return .primary }
        return .secondary
    }
}
