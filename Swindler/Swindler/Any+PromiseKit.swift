//
//  Any+PromiseKit.swift
//
//  Created by Daniel Tartaglia on 11/4/15.
//  Copyright © 2015. MIT License.
//

import PromiseKit

/**
Waits on all provided promises.
`any` waits on all provided promises, it rejects only if all of the promises rejected, otherwise it fulfills with values from the fulfilled promises.
- Returns: A new promise that resolves once all the provided promises resolve.
*/
public func any<T>(promises: [Promise<T>], onError: (Int, ErrorType) -> ()) -> Promise<[T]> {
  guard !promises.isEmpty else { return Promise<[T]>([]) }
  return Promise<[T]> { fulfill, reject in
    var values = [T]()
    var countdown = promises.count
    for (index, promise) in promises.enumerate() {
      promise.then { value in
        values.append(value)
      }.always {
        --countdown
        if countdown == 0 {
          if values.isEmpty {
            reject(AnyError.Any)
          }
          else {
            fulfill(values)
          }
        }
      }.error { error in
        onError(index, error)
      }
    }
  }
}

public enum AnyError: ErrorType {
  case Any
}