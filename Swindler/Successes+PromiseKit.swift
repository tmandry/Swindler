//  Based on Any+PromiseKit.swift,
//  Created by Daniel Tartaglia on 11/4/15.
//  Copyright © 2015. MIT License.

import PromiseKit

/** Waits on all provided promises, then resolves to the result of the successful ones.
- Param onError: A callback that is called each time any promise fails, with the index of the
                 promise and the error.
- Returns: A new promise that resolves once all the provided promises resolve, containing an array
           of the results from the successful promises.
*/
public func successes<T>(_ promises: [Promise<T>], onError: @escaping (Int, Error) -> Void)
-> Promise<[T]> {
    guard !promises.isEmpty else { return Promise<[T]>(value: []) }
    return Promise<[T]> { fulfill, _ in
        var values = [T]()
        var countdown = promises.count
        for (index, promise) in promises.enumerated() {
            promise.then { value in
                values.append(value)
            }.always {
                countdown -= 1
                if countdown == 0 {
                    fulfill(values)
                }
            }.catch { error in
                onError(index, error)
            }
        }
    }
}
