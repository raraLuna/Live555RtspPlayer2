//
//  HTTPClient.swift
//  Live555RtspPlayer2
//
//  Created by yumi on 2/21/25.
//

import Foundation

enum ApiError: Error {
    case invalidUrl
    case inputJsonDecodingError
    case nsUrlError(Error) // <Foundation/NSURLError.h>
    case invalidHttpResponse
    case httpError(Int)
    case wasError(String)
    case noDataReceived
    case responseJsonDecodingError
}

class HTTPClient {
    
    func sendPostRequest<T: Codable, U: Codable>(urlString: String, interfaceId: String?, requestBody: T, responseType: U.Type, completion: @escaping (Result<U, ApiError>) -> Void) {
        // Define the URL
        guard let url = URL(string: urlString) else {
            print("Invalid URL")
            completion(.failure(.invalidUrl))
            return
        }
        print("sendPostRequest url \(url)")
        // Create the request
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        // added by swyang
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if interfaceId != nil {
            request.setValue(interfaceId, forHTTPHeaderField: "interface_id")
        }
        
        // Define the POST body
        do {
            request.httpBody = try JSONEncoder().encode(requestBody)
        } catch {
            print("Error encoding POST body: \(error)")
            completion(.failure(.inputJsonDecodingError))
            return
        }
        
        // Create the URL session
        let session = URLSession.shared
        
        print("sendPostRequest request Header: \(request.allHTTPHeaderFields ?? [:])")
        print("sendPostRequest inputParams: \(String(describing: requestBody))")
        
        // Create the data task
        let task = session.dataTask(with: request) { data, response, error in
            if let error = error {
                completion(.failure(.nsUrlError(error)))
                return
            }

            guard let httpResponse = response as? HTTPURLResponse else {
                print("Invalid response")
                completion(.failure(.invalidHttpResponse))
                return
            }
            print("sendPostRequest \(String(describing: interfaceId)) response.statusCode = \(String(describing: httpResponse.statusCode))")
            
            guard (200...299).contains(httpResponse.statusCode) else {
                print("HTTP error: \(httpResponse.statusCode)")
                completion(.failure(.httpError(httpResponse.statusCode)))
                return
            }
            

            if let resultStatus = httpResponse.allHeaderFields["result_status"] as? String, resultStatus != "0000" {
                print("result_status: \(resultStatus)")
                completion(.failure(.wasError(resultStatus)))
                return
            }
            
            guard let data = data else {
                print("No data received")
                completion(.failure(.noDataReceived))
                return
            }
            let responseString = String(data: data, encoding: .utf8)
            print("sendPostRequest responseString: \(responseString ?? "empty response data")")
            do {
                let responseObject = try JSONDecoder().decode(responseType, from: data)
                completion(.success(responseObject))
            } catch {
                completion(.failure(.responseJsonDecodingError))
            }
        }
        
        // Start the task
        task.resume()
    }
    
    func sendGetRequest<U: Codable>(urlString: String, interfaceId: String?, responseType: U.Type, completion: @escaping (Result<U, ApiError>) -> Void) {
        // Define the URL
        guard let url = URL(string: urlString) else {
            print("Invalid URL")
            completion(.failure(.invalidUrl))
            return
        }
        
        // Create the request
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        // added by swyang
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if interfaceId != nil {
            request.setValue(interfaceId, forHTTPHeaderField: "interface_id")
        }
        
        // Create the URL session
        let session = URLSession.shared
        
        // Create the data task
        let task = session.dataTask(with: request) { data, response, error in
            if let error = error {
                completion(.failure(.nsUrlError(error)))
                return
            }
            
            guard let httpResponse = response as? HTTPURLResponse else {
                print("Invalid response")
                completion(.failure(.invalidHttpResponse))
                return
            }
            print("sendGetRequest \(String(describing: interfaceId)) response.statusCode = \(String(describing: httpResponse.statusCode))")
            
            guard (200...299).contains(httpResponse.statusCode) else {
                print("HTTP error: \(httpResponse.statusCode)")
                completion(.failure(.httpError(httpResponse.statusCode)))
                return
            }
            

            if let resultStatus = httpResponse.allHeaderFields["result_status"] as? String, resultStatus != "0000" {
                print("result_status: \(resultStatus)")
                completion(.failure(.wasError(resultStatus)))
                return
            }
            
            guard let data = data else {
                print("No data received")
                completion(.failure(.noDataReceived))
                return
            }
            let responseString = String(data: data, encoding: .utf8)
            print("sendGetRequest responseString: \(responseString ?? "empty response data")")
            do {
                let responseObject = try JSONDecoder().decode(responseType, from: data)
                completion(.success(responseObject))
            } catch {
                completion(.failure(.responseJsonDecodingError))
            }
        }
        
        // Start the task
        task.resume()
    }
}
