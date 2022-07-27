// This source code is dual-licensed under the Mozilla Public License ("MPL"),
// version 2.0 and the Apache License ("ASL"), version 2.0.
//
// The ASL v2.0:
//
// ---------------------------------------------------------------------------
// Copyright 2017-2022 VMware, Inc. or its affiliates.
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//    https://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.
// ---------------------------------------------------------------------------
//
// The MPL v2.0:
//
// ---------------------------------------------------------------------------
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2007-2022 VMware, Inc. or its affiliates.  All rights reserved.
//
// Alternatively, the contents of this file may be used under the terms
// of the Apache Standard license (the "ASL License"), in which case the
// provisions of the ASL License are applicable instead of those
// above. If you wish to allow use of your version of this file only
// under the terms of the ASL License and not to allow others to use
// your version of this file under the MPL, indicate your decision by
// deleting the provisions above and replace them with the notice and
// other provisions required by the ASL License. If you do not delete
// the provisions above, a recipient may use your version of this file
// under either the MPL or the ASL License.
// ---------------------------------------------------------------------------

import XCTest

// see https://github.com/rabbitmq/rabbitmq-objc-client/blob/master/CONTRIBUTING.md
// to set up your system for running integration tests
class OriginalIntegrationTest: XCTestCase {
    let plainEndpoint = IntegrationHelper.defaultEndpoint

    func testBasicGet() {
        let frameMaxRequiringTwoFrames = 4096
        var messageContent = ""
        for _ in 1...(frameMaxRequiringTwoFrames - RMQEmptyFrameSize) {
            messageContent += "a"
        }
        messageContent += "bb"

        let conn = RMQConnection(
            uri: plainEndpoint,
            tlsOptions: RMQTLSOptions.fromURI(plainEndpoint),
            delegate: nil
        )
        conn.start()
        defer { conn.blockingClose() }

        let ch = conn.createChannel()
        let src = ch.fanout("src", options: [.autoDelete])
        let dst = ch.fanout("dest", options: [.autoDelete])
        let q = ch.queue("", options: [.autoDelete, .exclusive])

        dst.bind(src)
        q.bind(dst)

        let body = messageContent.data(using: String.Encoding.utf8)!

        src.publish(body)

        let semaphore = DispatchSemaphore(value: 0)
        let expected = RMQMessage(
            body: body,
            consumerTag: "",
            deliveryTag: 1,
            redelivered: false,
            exchangeName: src.name,
            routingKey: "",
            properties: (RMQBasicProperties.defaultProperties() as! [RMQValue & RMQBasicValue])
        )
        var actual: RMQMessage?
        q.pop { m in
            actual = m
            semaphore.signal()
        }

        XCTAssertEqual(.success, semaphore.wait(timeout: TestHelper.dispatchTimeFromNow(2)),
                       "Timed out waiting for pop block to execute")
        XCTAssertEqual(expected, actual)
    }

    func testBlockingCloseIsIdempotent() {
        let conn = RMQConnection()
        conn.start {
            _ = conn.createChannel()

            for _ in 1...50 {
                conn.blockingClose()
            }
        }
    }

    func testClientChannelCloseCausesFutureOperationsToFail() {
        let delegate = ConnectionDelegateSpy()
        let conn = RMQConnection(uri: plainEndpoint, delegate: delegate, recoverAfter: 0)
        conn.start()
        defer { conn.blockingClose() }

        let ch = conn.createChannel()

        ch.close()

        XCTAssert(
            TestHelper.pollUntil(30) {
                ch.basicQos(1, global: false)
                return delegate.lastChannelError?._code == RMQError.channelClosed.rawValue
            }
        )
    }

    func testServerChannelCloseCausesFutureOperationsToFail() {
        let delegate = ConnectionDelegateSpy()
        let conn = RMQConnection(uri: plainEndpoint, delegate: delegate, recoverAfter: 0)
        conn.start()
        defer { conn.blockingClose() }

        let ch = conn.createChannel()

        causeServerChannelClose(ch)

        XCTAssert(
            TestHelper.pollUntil(5) {
                return delegate.lastChannelError?._code == RMQError.notFound.rawValue
            }
        )

        XCTAssert(
            TestHelper.pollUntil(2) {
                ch.basicQos(1, global: false)
                return delegate.lastChannelError?._code == RMQError.channelClosed.rawValue
            }
        )
    }

    fileprivate func causeServerChannelClose(_ ch: RMQChannel) {
        ch.basicPublish("".data(using: String.Encoding.utf8)!, routingKey: "irrelevant",
                        exchange: "a non-existent exchange", properties: [], options: [])
    }
}
