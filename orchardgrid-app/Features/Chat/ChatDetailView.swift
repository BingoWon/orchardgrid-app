/**
 * ChatDetailView.swift
 * Chat interface with streaming Apple Foundation Model responses
 */

import PhotosUI
import SwiftUI

#if os(macOS)
  import AppKit
#else
  import UIKit
#endif

struct ChatDetailView: View {
  let conversationId: UUID
  @Environment(ChatManager.self) private var chatManager
  @State private var inputText = ""
  @State private var selectedPhotoItem: PhotosPickerItem?
  @State private var attachedImageFilename: String?
  @State private var isLoadingPhoto = false
  @FocusState private var isInputFocused: Bool

  private var conversation: Conversation? {
    chatManager.conversation(for: conversationId)
  }

  private var isStreaming: Bool {
    chatManager.respondingConversationId == conversationId
  }

  var body: some View {
    VStack(spacing: 0) {
      messageList
      Divider()
      tokenUsageBadge
      inputBar
    }
    .navigationTitle(conversation?.title ?? String(localized: "Chat"))
    .toolbarRole(.editor)
    .toolbarTitleDisplayMode(.inlineLarge)
    .onDisappear { cleanupIfEmpty() }
  }

  // MARK: - Message List

  private var messageList: some View {
    ScrollViewReader { proxy in
      ScrollView {
        LazyVStack(spacing: 12) {
          if let messages = conversation?.messages, !messages.isEmpty {
            ForEach(messages) { message in
              MessageBubble(message: message)
                .id(message.id)
            }
          } else if !isStreaming {
            welcomePrompt
          }

          if isStreaming, !chatManager.streamingText.isEmpty {
            MessageBubble(
              message: Message(role: .assistant, content: chatManager.streamingText)
            )
            .id("streaming")
          }

          if isStreaming, chatManager.streamingText.isEmpty {
            HStack {
              TypingIndicator()
              Spacer()
            }
            .id("typing")
          }
        }
        .padding()
      }
      .onChange(of: conversation?.messages.count) { _, _ in
        scrollToBottom(proxy)
      }
      .onChange(of: isStreaming) { _, streaming in
        if streaming { scrollToBottom(proxy) }
      }
      .onAppear {
        scrollToBottom(proxy)
      }
    }
  }

  // MARK: - Welcome Prompt

  private var welcomePrompt: some View {
    VStack(spacing: 16) {
      Image(systemName: "apple.intelligence")
        .font(.system(size: 40))
        .foregroundStyle(.secondary)
        .symbolColorRenderingMode(.gradient)

      Text("Apple's built-in AI")
        .font(.title3)
        .fontWeight(.semibold)

      Text("Chat, create images, and more — entirely on-device.")
        .font(.subheadline)
        .foregroundStyle(.secondary)
        .multilineTextAlignment(.center)
    }
    .frame(maxWidth: .infinity)
    .padding(.vertical, 60)
  }

  // MARK: - Token Usage Badge

  @ViewBuilder
  private var tokenUsageBadge: some View {
    if let info = chatManager.tokenUsageInfo(for: conversationId) {
      let percent = Float(info.tokens) / Float(info.contextSize)
      let color: Color = percent > 0.85 ? .red : percent > 0.6 ? .orange : .secondary

      HStack(spacing: 4) {
        Image(systemName: "gauge.with.dots.needle.33percent")
          .font(.caption2)
        Text(
          "\(info.tokens.formatted()) / \(info.contextSize.formatted())"
        )
        .monospacedDigit()
        Text("·")
        Text(
          percent.formatted(.percent.precision(.fractionLength(0)))
        )
      }
      .font(.caption2)
      .foregroundStyle(color)
      .padding(.horizontal, 10)
      .padding(.vertical, 4)
      .frame(maxWidth: .infinity, alignment: .trailing)
    }
  }

  // MARK: - Input Bar

  private var inputBar: some View {
    VStack(spacing: 0) {
      if let filename = attachedImageFilename {
        attachmentPreview(filename: filename)
      }

      HStack(alignment: .bottom, spacing: 8) {
        if isLoadingPhoto {
          ProgressView()
            .controlSize(.small)
            .frame(width: 36, height: 36)
        } else {
          PhotosPicker(selection: $selectedPhotoItem, matching: .images) {
            Image(systemName: "photo.badge.plus")
              .font(.system(size: 20))
              .foregroundStyle(.secondary)
              .frame(width: 36, height: 36)
              .contentShape(Rectangle())
          }
          .buttonStyle(.plain)
          .onChange(of: selectedPhotoItem) { _, item in
            Task { await loadSelectedPhoto(item) }
          }
        }

        TextField("Message", text: $inputText, axis: .vertical)
          .textFieldStyle(.plain)
          .lineLimit(1...5)
          .focused($isInputFocused)
          .padding(.horizontal, 14)
          .padding(.vertical, 10)
          .background(.fill.tertiary, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
          .onKeyPress(.return, phases: .down) { press in
            if press.modifiers.contains(.shift) {
              return .ignored
            }
            sendMessage()
            return .handled
          }

        if chatManager.isResponding {
          Button {
            chatManager.stopResponding()
          } label: {
            Image(systemName: "stop.circle.fill")
              .font(.system(size: 32))
              .symbolRenderingMode(.hierarchical)
              .foregroundStyle(.red)
          }
          .buttonStyle(.plain)
        } else {
          Button {
            sendMessage()
          } label: {
            Image(systemName: "arrow.up.circle.fill")
              .font(.system(size: 32))
              .symbolRenderingMode(.hierarchical)
              .foregroundStyle(canSend ? Color.blue : Color.gray.opacity(0.3))
          }
          .disabled(!canSend)
          .buttonStyle(.plain)
        }
      }
      .padding(.horizontal, 16)
      .padding(.vertical, 10)
    }
  }

  private func attachmentPreview(filename: String) -> some View {
    let url = ChatImages.directory.appendingPathComponent(filename)
    return HStack(spacing: 8) {
      thumbnailImage(url: url)
        .frame(width: 56, height: 56)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

      VStack(alignment: .leading, spacing: 2) {
        Text("Reference photo")
          .font(.caption)
          .fontWeight(.medium)
        Text("Will be used for image generation")
          .font(.caption2)
          .foregroundStyle(.secondary)
      }

      Spacer()

      Button {
        withAnimation(.easeOut(duration: 0.2)) {
          removeAttachment()
        }
      } label: {
        Image(systemName: "xmark.circle.fill")
          .font(.system(size: 20))
          .foregroundStyle(.secondary)
      }
      .buttonStyle(.plain)
    }
    .padding(.horizontal, 16)
    .padding(.vertical, 8)
    .background(.fill.quaternary)
    .transition(.move(edge: .bottom).combined(with: .opacity))
  }

  @ViewBuilder
  private func thumbnailImage(url: URL) -> some View {
    #if os(macOS)
      if let nsImage = NSImage(contentsOf: url) {
        Image(nsImage: nsImage)
          .resizable()
          .aspectRatio(contentMode: .fill)
      } else {
        imagePlaceholder
      }
    #else
      if let uiImage = UIImage(contentsOfFile: url.path) {
        Image(uiImage: uiImage)
          .resizable()
          .aspectRatio(contentMode: .fill)
      } else {
        imagePlaceholder
      }
    #endif
  }

  private var imagePlaceholder: some View {
    Rectangle()
      .fill(.fill.quaternary)
      .overlay {
        Image(systemName: "photo")
          .foregroundStyle(.tertiary)
      }
  }

  // MARK: - Helpers

  private var canSend: Bool {
    !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      && !chatManager.isResponding
      && chatManager.isModelAvailable
  }

  private func sendMessage() {
    let content = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !content.isEmpty else { return }
    inputText = ""
    let images = attachedImageFilename.map { [$0] } ?? []
    attachedImageFilename = nil
    selectedPhotoItem = nil
    chatManager.sendMessage(content, imageFilenames: images, in: conversationId)
  }

  private func loadSelectedPhoto(_ item: PhotosPickerItem?) async {
    guard let item else { return }
    isLoadingPhoto = true
    defer { isLoadingPhoto = false }

    guard let data = try? await item.loadTransferable(type: Data.self) else { return }

    let ext = ChatImages.fileExtension(for: data)
    let filename = "ref_\(UUID().uuidString).\(ext)"
    let dir = ChatImages.directory
    let url = dir.appendingPathComponent(filename)

    do {
      try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
      try data.write(to: url, options: .atomic)
      withAnimation(.easeOut(duration: 0.2)) {
        attachedImageFilename = filename
      }
    } catch {
      Logger.error(.app, "Failed to save attachment: \(error.localizedDescription)")
    }
  }

  private func removeAttachment() {
    if let filename = attachedImageFilename {
      let url = ChatImages.directory.appendingPathComponent(filename)
      try? FileManager.default.removeItem(at: url)
    }
    attachedImageFilename = nil
    selectedPhotoItem = nil
  }

  private func scrollToBottom(_ proxy: ScrollViewProxy) {
    withAnimation(.easeOut(duration: 0.2)) {
      if isStreaming {
        proxy.scrollTo(
          chatManager.streamingText.isEmpty ? "typing" : "streaming",
          anchor: .bottom
        )
      } else if let lastId = conversation?.messages.last?.id {
        proxy.scrollTo(lastId, anchor: .bottom)
      }
    }
  }

  private func cleanupIfEmpty() {
    if let conv = conversation, conv.messages.isEmpty {
      chatManager.deleteConversation(id: conv.id)
    }
  }
}

// MARK: - Message Bubble

private struct MessageBubble: View {
  let message: Message

  var body: some View {
    HStack(alignment: .bottom, spacing: 4) {
      if message.role == .user {
        Spacer(minLength: 48)
        if !message.content.isEmpty { copyButton }
      }

      VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 8) {
        if message.role == .user, message.hasImages {
          ForEach(message.imageFilenames, id: \.self) { filename in
            ChatImageView(filename: filename, compact: true)
          }
        }

        if !message.content.isEmpty {
          messageContent
        }

        if message.role == .assistant {
          ForEach(message.imageFilenames, id: \.self) { filename in
            ChatImageView(filename: filename, compact: false)
          }
        }
      }

      if message.role == .assistant {
        if !message.content.isEmpty { copyButton }
        Spacer(minLength: 48)
      }
    }
  }

  @ViewBuilder
  private var messageContent: some View {
    if message.role == .assistant {
      ChatMarkdownView(content: message.content)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
          RoundedRectangle(cornerRadius: 16, style: .continuous)
            .fill(.fill.tertiary)
        )
    } else {
      Text(message.content)
        .font(.body)
        .textSelection(.enabled)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .foregroundStyle(.white)
        .background(
          RoundedRectangle(cornerRadius: 16, style: .continuous)
            .fill(.blue.gradient)
        )
    }
  }

  private var copyButton: some View {
    CopyButton(text: message.content, showLabel: false)
      .font(.caption2)
  }
}

// MARK: - Chat Image View

private struct ChatImageView: View {
  let filename: String
  var compact: Bool = false
  @State private var loadedImage: LoadedImage?
  @State private var isFullscreen = false

  var body: some View {
    Group {
      if let loadedImage {
        imageContent(loadedImage)
      } else {
        placeholder
      }
    }
    .onAppear { loadImage() }
  }

  private func imageContent(_ loaded: LoadedImage) -> some View {
    #if os(macOS)
      let img = Image(nsImage: loaded.image)
    #else
      let img = Image(uiImage: loaded.image)
    #endif

    let maxDim: CGFloat = compact ? 80 : 320
    let radius: CGFloat = compact ? 10 : 12

    return
      img
      .resizable()
      .aspectRatio(contentMode: compact ? .fill : .fit)
      .frame(maxWidth: maxDim, maxHeight: maxDim)
      .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
      .overlay(
        RoundedRectangle(cornerRadius: radius, style: .continuous)
          .strokeBorder(.primary.opacity(0.08), lineWidth: 0.5)
      )
      .shadow(
        color: .black.opacity(compact ? 0.05 : 0.1), radius: compact ? 4 : 8, y: compact ? 2 : 4
      )
      .onTapGesture { isFullscreen = true }
      .sheet(isPresented: $isFullscreen) {
        ImagePreviewSheet(loaded: loaded)
      }
      .transition(.opacity.combined(with: .scale(scale: 0.95)))
  }

  private var placeholder: some View {
    let size: CGFloat = compact ? 80 : 200
    return RoundedRectangle(cornerRadius: compact ? 10 : 12, style: .continuous)
      .fill(.fill.quaternary)
      .frame(width: size, height: size)
      .overlay {
        if compact {
          ProgressView().controlSize(.small)
        } else {
          VStack(spacing: 8) {
            ProgressView()
            Text("Loading…")
              .font(.caption)
              .foregroundStyle(.secondary)
          }
        }
      }
  }

  private func loadImage() {
    let url = ChatImages.directory.appendingPathComponent(filename)
    #if os(macOS)
      guard let image = NSImage(contentsOf: url) else { return }
      withAnimation(.easeOut(duration: 0.3)) {
        loadedImage = LoadedImage(image: image)
      }
    #else
      guard let image = UIImage(contentsOfFile: url.path) else { return }
      withAnimation(.easeOut(duration: 0.3)) {
        loadedImage = LoadedImage(image: image)
      }
    #endif
  }
}

// MARK: - Platform Image Wrapper

#if os(macOS)
  private struct LoadedImage {
    let image: NSImage
  }
#else
  private struct LoadedImage {
    let image: UIImage
  }
#endif

// MARK: - Full-Screen Image Preview

private struct ImagePreviewSheet: View {
  let loaded: LoadedImage
  @Environment(\.dismiss) private var dismiss

  var body: some View {
    NavigationStack {
      #if os(macOS)
        let img = Image(nsImage: loaded.image)
      #else
        let img = Image(uiImage: loaded.image)
      #endif

      img
        .resizable()
        .aspectRatio(contentMode: .fit)
        .padding()
        .frame(minWidth: 400, minHeight: 400)
        .navigationTitle(String(localized: "Image Preview"))
        .toolbarTitleDisplayMode(.inline)
        .toolbar {
          ToolbarItem(placement: .confirmationAction) {
            Button("Done") { dismiss() }
          }
        }
    }
  }
}

// MARK: - Typing Indicator

private struct TypingIndicator: View {
  @State private var isAnimating = false

  var body: some View {
    HStack(spacing: 5) {
      ForEach(0..<3, id: \.self) { index in
        Circle()
          .fill(.secondary)
          .frame(width: 7, height: 7)
          .scaleEffect(isAnimating ? 1.0 : 0.5)
          .opacity(isAnimating ? 1.0 : 0.4)
          .animation(
            .easeInOut(duration: 0.5)
              .repeatForever(autoreverses: true)
              .delay(Double(index) * 0.15),
            value: isAnimating
          )
      }
    }
    .padding(.horizontal, 14)
    .padding(.vertical, 12)
    .background(.fill.tertiary, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    .onAppear { isAnimating = true }
  }
}

#Preview {
  NavigationStack {
    ChatDetailView(conversationId: UUID())
      .environment(ChatManager())
  }
}
