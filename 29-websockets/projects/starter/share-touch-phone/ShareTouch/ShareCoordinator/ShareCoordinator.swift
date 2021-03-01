/// Copyright (c) 2021 Razeware LLC
///
/// Permission is hereby granted, free of charge, to any person obtaining a copy
/// of this software and associated documentation files (the "Software"), to deal
/// in the Software without restriction, including without limitation the rights
/// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
/// copies of the Software, and to permit persons to whom the Software is
/// furnished to do so, subject to the following conditions:
///
/// The above copyright notice and this permission notice shall be included in
/// all copies or substantial portions of the Software.
///
/// Notwithstanding the foregoing, you may not use, copy, modify, merge, publish,
/// distribute, sublicense, create a derivative work, and/or sell copies of the
/// Software in any work that is designed, intended, or marketed for pedagogical or
/// instructional purposes related to programming, coding, application development,
/// or information technology.  Permission for such use, copying, modification,
/// merger, publication, distribution, sublicensing, creation of derivative works,
/// or sale is expressly withheld.
///
/// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
/// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
/// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
/// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
/// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
/// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
/// THE SOFTWARE.

import SwiftUI
import Foundation
import Combine

class ShareCoordinator: NSObject, ObservableObject, URLSessionWebSocketDelegate {
    @Published private(set) var participants: [String: SharedTouch] = [:] {
        didSet {
            ordered = participants.map(\.value).sorted { $0.participant < $1.participant }
        }
    }
    @Published var ordered: [SharedTouch] = []

    @Binding var color: Color
    @Published var position: UnitPoint = .center

    private var cancellables = [AnyCancellable]()
    let url: String

    init(url: String, color: Binding<Color>) {
        self.url = url
        self._color = color
        super.init()

        $position
            .sink(receiveCompletion: { _ in
                fatalError("this shouldn't happen?")
            }, receiveValue: { [weak self] update in
                self?.send(position: update)
            })
            .store(in: &cancellables)
    }

    private func send(position: RelativePoint) {
        guard let str = try? JSONEncoder().encode(position).string else {
            print("couldn't encode update: \(position)")
            return
        }

        self.ws?.send(.string(str)) { err in
            guard let err = err else { return }
            print("error: \(err)")
        }
    }

    private var ws: URLSessionWebSocketTask? = nil

    private func on(msg: Message) {
        DispatchQueue.main.async {
            switch msg.update {
            case .moved(let pt):
                self.participants[msg.participant]?.position = .init(x: pt.x, y: pt.y)
            case .joined(let shared):
                self.participants[msg.participant] = shared
            case .left:
                self.participants[msg.participant] = nil
            }
        }
    }

    private lazy var session: URLSession = URLSession(configuration: .default,
                                                      delegate: self,
                                                      delegateQueue: nil)

    func connect() {
        guard ws == nil else { fatalError() }
        let comps = color.components
        let query = "r=\(comps.r)&g=\(comps.g)&b=\(comps.b)&a=\(comps.a)&x=\(position.x)&y=\(position.y)"
        let url = URL(string: "\(self.url)?\(query)")!
        let ws = session.webSocketTask(with: url)
        self.ws = ws
        listen()

        ws.resume()
    }

    func disconnect() {
        ws?.cancel(with: .goingAway, reason: nil)
    }

    var keepListening = true

    func listen() {
        ws?.receive { [weak self] result in
            switch result {
            case .success(let raw):
                do {
                    let msg = try Message(raw)
                    self?.on(msg: msg)
                } catch {
                    print(error.localizedDescription)
                    print("msg: \(raw)")
                }
                if self?.keepListening == true {
                    self?.listen()
                }
            case .failure(let err):
                print("error: \(err)")
                self?.ws = nil
                self?.connect()
            }
        }
    }


    deinit {
        ws?.cancel()
    }

    func cancel() {
        ws?.cancel(with: .goingAway, reason: nil)
        ws = nil
    }

    func urlSession(
        _ session: URLSession,
        webSocketTask: URLSessionWebSocketTask,
        didOpenWithProtocol protocol: String?) {
        listen()
        webSocketTask.resume()
    }

    func urlSession(
        _ session: URLSession,
        webSocketTask: URLSessionWebSocketTask,
        didCloseWith closeCode: URLSessionWebSocketTask.CloseCode,
        reason: Data?) {
        print("didClose")
    }
}

extension Decodable {
    init(_ msg: URLSessionWebSocketTask.Message) throws {
        let js = JSONDecoder()
        let data: Data
        switch msg {
        case .data(let d):
            data = d
        case .string(let s):
            data = .init(s.utf8)
        @unknown default:
            throw "unknown"
        }
        self = try js.decode(Self.self, from: data)
    }
}
