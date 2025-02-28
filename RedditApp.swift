import SwiftUI
import Combine
import WebKit
import AuthenticationServices
import AVKit
import Kingfisher

// MARK: - App Structure
@main
struct RedditCloneApp: App {
    @StateObject private var authManager = RedditAuthManager()
    @StateObject private var dataStore = RedditDataStore()
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(authManager)
                .environmentObject(dataStore)
                .onOpenURL { url in
                    // Handle deep links for auth callbacks
                    if url.scheme == "redditclone" {
                        authManager.handleRedirectURL(url)
                    }
                }
        }
    }
}

// MARK: - Models

struct RedditPost: Identifiable, Decodable {
    let id: String
    let title: String
    let author: String
    let created: Double
    let thumbnail: String?
    let selftext: String
    let score: Int
    let num_comments: Int
    let url: String
    let is_self: Bool
    let permalink: String
    let domain: String
    let post_hint: String?
    let is_video: Bool
    let media: Media?
    let preview: Preview?
    let gallery_data: GalleryData?
    let crosspost_parent_list: [RedditPost]?
    
    var createdDate: Date {
        return Date(timeIntervalSince1970: created)
    }
    
    var hasGallery: Bool {
        return gallery_data != nil
    }
    
    var contentType: PostContentType {
        if is_self {
            return .selfText
        } else if hasGallery {
            return .gallery
        } else if let hint = post_hint {
            if hint == "image" {
                return .image
            } else if hint == "hosted:video" || hint == "rich:video" {
                return .video
            } else if hint == "link" {
                return .link
            }
        } else if is_video {
            return .video
        } else if let mediaData = media, mediaData.reddit_video != nil {
            return .video
        } else if let previewData = preview, 
                  let firstImage = previewData.images.first, 
                  let source = firstImage.source {
            return .image
        } else if url.lowercased().hasSuffix(".jpg") || 
                  url.lowercased().hasSuffix(".jpeg") || 
                  url.lowercased().hasSuffix(".png") || 
                  url.lowercased().hasSuffix(".gif") {
            return .image
        } else if url.lowercased().hasSuffix(".mp4") || 
                  url.lowercased().hasSuffix(".mov") || 
                  url.lowercased().hasSuffix(".webm") || 
                  url.contains("v.redd.it") || 
                  url.contains("youtube.com") || 
                  url.contains("youtu.be") {
            return .video
        }
        
        return .link
    }
    
    enum CodingKeys: String, CodingKey {
        case id, title, author, created, thumbnail, selftext, score, num_comments, url, is_self, permalink, domain, post_hint, is_video, media, preview, gallery_data, crosspost_parent_list
    }
}

enum PostContentType {
    case selfText, image, video, link, gallery
}

struct Media: Decodable {
    let reddit_video: RedditVideo?
    let oembed: OEmbed?
    
    enum CodingKeys: String, CodingKey {
        case reddit_video, oembed
    }
}

struct RedditVideo: Decodable {
    let fallback_url: String
    let hls_url: String?
    let dash_url: String?
    let duration: Int?
    let height: Int?
    let width: Int?
    
    enum CodingKeys: String, CodingKey {
        case fallback_url, hls_url, dash_url, duration, height, width
    }
}

struct OEmbed: Decodable {
    let provider_url: String?
    let title: String?
    let thumbnail_url: String?
    let html: String?
    
    enum CodingKeys: String, CodingKey {
        case provider_url, title, thumbnail_url, html
    }
}

struct Preview: Decodable {
    let images: [ImagePreview]
    let reddit_video_preview: RedditVideo?
    
    enum CodingKeys: String, CodingKey {
        case images, reddit_video_preview
    }
}

struct ImagePreview: Decodable {
    let source: ImageSource?
    let resolutions: [ImageSource]
    let variants: ImageVariants?
    
    enum CodingKeys: String, CodingKey {
        case source, resolutions, variants
    }
}

struct ImageSource: Decodable {
    let url: String
    let width: Int
    let height: Int
    
    enum CodingKeys: String, CodingKey {
        case url, width, height
    }
}

struct ImageVariants: Decodable {
    let gif: ImagePreview?
    let mp4: ImagePreview?
    
    enum CodingKeys: String, CodingKey {
        case gif, mp4
    }
}

struct GalleryData: Decodable {
    let items: [GalleryItem]
    
    enum CodingKeys: String, CodingKey {
        case items
    }
}

struct GalleryItem: Decodable, Identifiable {
    let id: Int
    let media_id: String
    
    enum CodingKeys: String, CodingKey {
        case id, media_id
    }
}

struct RedditComment: Identifiable, Decodable {
    let id: String
    let author: String
    let body: String
    let created: Double
    let score: Int
    let replies: CommentReplies?
    
    var createdDate: Date {
        return Date(timeIntervalSince1970: created)
    }
    
    enum CodingKeys: String, CodingKey {
        case id, author, body, created, score, replies
    }
}

struct CommentReplies: Decodable {
    let data: CommentData?
    
    enum CodingKeys: String, CodingKey {
        case data
    }
}

struct CommentData: Decodable {
    let children: [CommentChild]?
    
    enum CodingKeys: String, CodingKey {
        case children
    }
}

struct CommentChild: Decodable {
    let data: RedditComment?
    
    enum CodingKeys: String, CodingKey {
        case data
    }
}

struct Subreddit: Identifiable {
    let id = UUID()
    let name: String
    let displayName: String
}

struct LinkMetadata: Identifiable {
    let id = UUID()
    let url: String
    var title: String = ""
    var description: String = ""
    var imageURL: String? = nil
    var siteName: String = ""
}

// MARK: - Authentication Manager
class RedditAuthManager: ObservableObject {
    @Published var isAuthenticated = false
    @Published var accessToken: String = ""
    @Published var username: String = ""
    
    private let clientID = "YOUR_CLIENT_ID" // Replace with your Reddit API client ID
    private let redirectURI = "redditclone://auth"
    private let responseType = "code"
    private let duration = "permanent"
    private let scope = "identity read vote save history"
    
    var authURL: URL {
        var components = URLComponents(string: "https://www.reddit.com/api/v1/authorize")!
        components.queryItems = [
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "response_type", value: responseType),
            URLQueryItem(name: "state", value: UUID().uuidString),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "duration", value: duration),
            URLQueryItem(name: "scope", value: scope)
        ]
        return components.url!
    }
    
    func handleRedirectURL(_ url: URL) {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: true),
              let queryItems = components.queryItems,
              let code = queryItems.first(where: { $0.name == "code" })?.value else {
            return
        }
        
        exchangeCodeForToken(code)
    }
    
    private func exchangeCodeForToken(_ code: String) {
        guard let url = URL(string: "https://www.reddit.com/api/v1/access_token") else { return }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        
        let authString = "\(clientID):"
        let authData = authString.data(using: .utf8)!
        let base64Auth = authData.base64EncodedString()
        
        request.addValue("Basic \(base64Auth)", forHTTPHeaderField: "Authorization")
        request.addValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        
        let body = "grant_type=authorization_code&code=\(code)&redirect_uri=\(redirectURI)"
        request.httpBody = body.data(using: .utf8)
        
        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            guard let data = data, error == nil else { return }
            
            do {
                if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let token = json["access_token"] as? String {
                    DispatchQueue.main.async {
                        self?.accessToken = token
                        self?.isAuthenticated = true
                        self?.fetchUsername()
                    }
                }
            } catch {
                print("Token exchange error: \(error)")
            }
        }.resume()
    }
    
    func fetchUsername() {
        guard !accessToken.isEmpty else { return }
        
        guard let url = URL(string: "https://oauth.reddit.com/api/v1/me") else { return }
        
        var request = URLRequest(url: url)
        request.addValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.addValue("RedditClone/1.0", forHTTPHeaderField: "User-Agent")
        
        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            guard let data = data, error == nil else { return }
            
            do {
                if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let name = json["name"] as? String {
                    DispatchQueue.main.async {
                        self?.username = name
                    }
                }
            } catch {
                print("Username fetch error: \(error)")
            }
        }.resume()
    }
    
    func signOut() {
        accessToken = ""
        username = ""
        isAuthenticated = false
    }
}

// MARK: - Data Store
class RedditDataStore: ObservableObject {
    @Published var posts: [RedditPost] = []
    @Published var comments: [RedditComment] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var linkMetadataCache: [String: LinkMetadata] = [:]
    @Published var subreddits: [Subreddit] = [
        Subreddit(name: "all", displayName: "All"),
        Subreddit(name: "popular", displayName: "Popular"),
        Subreddit(name: "news", displayName: "News"),
        Subreddit(name: "pics", displayName: "Pics"),
        Subreddit(name: "funny", displayName: "Funny"),
        Subreddit(name: "AskReddit", displayName: "Ask Reddit"),
        Subreddit(name: "videos", displayName: "Videos"),
        Subreddit(name: "gifs", displayName: "Gifs"),
        Subreddit(name: "gaming", displayName: "Gaming")
    ]
    
    func fetchPosts(for subreddit: String, token: String, limit: Int = 25) {
        isLoading = true
        errorMessage = nil
        
        let urlString = "https://oauth.reddit.com/r/\(subreddit)/hot.json?limit=\(limit)"
        guard let url = URL(string: urlString) else {
            errorMessage = "Invalid URL"
            isLoading = false
            return
        }
        
        var request = URLRequest(url: url)
        request.addValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.addValue("RedditClone/1.0", forHTTPHeaderField: "User-Agent")
        
        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            DispatchQueue.main.async {
                self?.isLoading = false
                
                if let error = error {
                    self?.errorMessage = error.localizedDescription
                    return
                }
                
                guard let data = data else {
                    self?.errorMessage = "No data received"
                    return
                }
                
                do {
                    if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                       let dataObj = json["data"] as? [String: Any],
                       let children = dataObj["children"] as? [[String: Any]] {
                        
                        var newPosts: [RedditPost] = []
                        
                        for child in children {
                            if let postData = child["data"] as? [String: Any],
                               let postJSON = try? JSONSerialization.data(withJSONObject: postData),
                               let post = try? JSONDecoder().decode(RedditPost.self, from: postJSON) {
                                newPosts.append(post)
                                
                                // Preload link metadata for links
                                if post.contentType == .link {
                                    self?.fetchLinkMetadata(for: post.url)
                                }
                            }
                        }
                        
                        self?.posts = newPosts
                    }
                } catch {
                    self?.errorMessage = "Failed to parse data: \(error.localizedDescription)"
                }
            }
        }.resume()
    }
    
    func fetchComments(for postID: String, subreddit: String, token: String) {
        isLoading = true
        errorMessage = nil
        
        let urlString = "https://oauth.reddit.com/r/\(subreddit)/comments/\(postID).json"
        guard let url = URL(string: urlString) else {
            errorMessage = "Invalid URL"
            isLoading = false
            return
        }
        
        var request = URLRequest(url: url)
        request.addValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.addValue("RedditClone/1.0", forHTTPHeaderField: "User-Agent")
        
        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            DispatchQueue.main.async {
                self?.isLoading = false
                
                if let error = error {
                    self?.errorMessage = error.localizedDescription
                    return
                }
                
                guard let data = data else {
                    self?.errorMessage = "No data received"
                    return
                }
                
                do {
                    if let jsonArray = try JSONSerialization.jsonObject(with: data) as? [[String: Any]],
                       jsonArray.count > 1,
                       let commentsData = jsonArray[1]["data"] as? [String: Any],
                       let children = commentsData["children"] as? [[String: Any]] {
                        
                        var newComments: [RedditComment] = []
                        
                        for child in children {
                            if let commentData = child["data"] as? [String: Any],
                               let commentJSON = try? JSONSerialization.data(withJSONObject: commentData),
                               let comment = try? JSONDecoder().decode(RedditComment.self, from: commentJSON) {
                                newComments.append(comment)
                            }
                        }
                        
                        self?.comments = newComments
                    }
                } catch {
                    self?.errorMessage = "Failed to parse comments: \(error.localizedDescription)"
                }
            }
        }.resume()
    }
    
    func fetchLinkMetadata(for urlString: String) {
        // Check cache first
        if linkMetadataCache[urlString] != nil {
            return
        }
        
        // Create a basic placeholder while loading
        let metadata = LinkMetadata(url: urlString)
        linkMetadataCache[urlString] = metadata
        
        // This would normally use OpenGraph or other metadata extraction
        // For this example, we'll use a basic simulation
        guard let url = URL(string: urlString) else { return }
        
        let task = URLSession.shared.dataTask(with: url) { [weak self] data, response, error in
            guard let data = data,
                  let string = String(data: data, encoding: .utf8) else {
                return
            }
            
            // Extract title (very basic approach)
            var title = ""
            if let titleRange = string.range(of: "<title>.*?</title>", options: .regularExpression) {
                title = String(string[titleRange])
                    .replacingOccurrences(of: "<title>", with: "")
                    .replacingOccurrences(of: "</title>", with: "")
            }
            
            // Extract description (very basic approach)
            var description = ""
            if let metaRange = string.range(of: "<meta name=\"description\" content=\".*?\">", options: .regularExpression) {
                let metaTag = String(string[metaRange])
                if let contentRange = metaTag.range(of: "content=\".*?\"", options: .regularExpression) {
                    description = String(metaTag[contentRange])
                        .replacingOccurrences(of: "content=\"", with: "")
                        .replacingOccurrences(of: "\"", with: "")
                }
            }
            
            // Extract image (very basic approach)
            var imageURL: String? = nil
            if let ogImageRange = string.range(of: "<meta property=\"og:image\" content=\".*?\">", options: .regularExpression) {
                let ogImageTag = String(string[ogImageRange])
                if let contentRange = ogImageTag.range(of: "content=\".*?\"", options: .regularExpression) {
                    imageURL = String(ogImageTag[contentRange])
                        .replacingOccurrences(of: "content=\"", with: "")
                        .replacingOccurrences(of: "\"", with: "")
                }
            }
            
            // Extract site name
            var siteName = ""
            if let urlComponents = URLComponents(url: url, resolvingAgainstBaseURL: false),
               let host = urlComponents.host {
                siteName = host.replacingOccurrences(of: "www.", with: "")
            }
            
            DispatchQueue.main.async {
                var updatedMetadata = self?.linkMetadataCache[urlString] ?? metadata
                updatedMetadata.title = title.isEmpty ? urlString : title
                updatedMetadata.description = description
                updatedMetadata.imageURL = imageURL
                updatedMetadata.siteName = siteName
                
                self?.linkMetadataCache[urlString] = updatedMetadata
            }
        }
        
        task.resume()
    }
}

// MARK: - Views

struct ContentView: View {
    @EnvironmentObject var authManager: RedditAuthManager
    
    var body: some View {
        Group {
            if authManager.isAuthenticated {
                MainTabView()
            } else {
                LoginView()
            }
        }
    }
}

struct LoginView: View {
    @EnvironmentObject var authManager: RedditAuthManager
    @State private var showWebView = false
    
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "bubble.left.fill")
                .resizable()
                .scaledToFit()
                .frame(width: 100, height: 100)
                .foregroundColor(.blue)
            
            Text("Reddit Clone")
                .font(.largeTitle)
                .fontWeight(.bold)
            
            Text("Inspired by Alien Blue")
                .font(.subheadline)
                .foregroundColor(.secondary)
            
            Button(action: {
                showWebView = true
            }) {
                Text("Login with Reddit")
                    .fontWeight(.semibold)
                    .foregroundColor(.white)
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(Color.blue)
                    .cornerRadius(10)
                    .padding(.horizontal, 50)
            }
            .sheet(isPresented: $showWebView) {
                RedditAuthWebView(url: authManager.authURL)
            }
        }
        .padding()
    }
}

struct RedditAuthWebView: UIViewRepresentable {
    let url: URL
    @Environment(\.presentationMode) var presentationMode
    @EnvironmentObject var authManager: RedditAuthManager
    
    func makeUIView(context: Context) -> WKWebView {
        let webView = WKWebView()
        webView.navigationDelegate = context.coordinator
        return webView
    }
    
    func updateUIView(_ webView: WKWebView, context: Context) {
        let request = URLRequest(url: url)
        webView.load(request)
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, WKNavigationDelegate {
        var parent: RedditAuthWebView
        
        init(_ parent: RedditAuthWebView) {
            self.parent = parent
        }
        
        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            if let url = navigationAction.request.url,
               url.scheme == "redditclone" {
                parent.authManager.handleRedirectURL(url)
                parent.presentationMode.wrappedValue.dismiss()
                decisionHandler(.cancel)
                return
            }
            decisionHandler(.allow)
        }
    }
}

struct MainTabView: View {
    @EnvironmentObject var authManager: RedditAuthManager
    
    var body: some View {
        TabView {
            SubredditListView()
                .tabItem {
                    Label("Subreddits", systemImage: "list.bullet")
                }
            
            SearchView()
                .tabItem {
                    Label("Search", systemImage: "magnifyingglass")
                }
            
            ProfileView()
                .tabItem {
                    Label("Profile", systemImage: "person.circle")
                }
        }
    }
}

struct SubredditListView: View {
    @EnvironmentObject var dataStore: RedditDataStore
    @State private var selectedSubreddit: Subreddit?
    @State private var showAddSubreddit = false
    @State private var newSubredditName = ""
    
    var body: some View {
        NavigationView {
            List(dataStore.subreddits) { subreddit in
                NavigationLink(destination: PostListView(subreddit: subreddit)) {
                    HStack {
                        Circle()
                            .fill(Color.blue.opacity(0.2))
                            .frame(width: 40, height: 40)
                            .overlay(
                                Text(subreddit.displayName.prefix(1))
                                    .foregroundColor(.blue)
                                    .fontWeight(.bold)
                            )
                        
                        Text(subreddit.displayName)
                            .fontWeight(.medium)
                    }
                    .padding(.vertical, 8)
                }
            }
            .navigationTitle("Subreddits")
            .navigationBarItems(trailing: Button(action: {
                showAddSubreddit = true
            }) {
                Image(systemName: "plus")
            })
            .sheet(isPresented: $showAddSubreddit) {
                VStack(spacing: 20) {
                    Text("Add Subreddit")
                        .font(.headline)
                    
                    TextField("Subreddit name", text: $newSubredditName)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .autocapitalization(.none)
                    
                    Button("Add") {
                        if !newSubredditName.isEmpty {
                            let name = newSubredditName.trimmingCharacters(in: .whitespacesAndNewlines)
                            dataStore.subreddits.append(Subreddit(name: name, displayName: name))
                            newSubredditName = ""
                            showAddSubreddit = false
                        }
                    }
                    .padding()
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(8)
                    
                    Button("Cancel") {
                        showAddSubreddit = false
                    }
                    .foregroundColor(.red)
                }
                .padding()
            }
        }
    }
}

struct PostListView: View {
    let subreddit: Subreddit
    @EnvironmentObject var dataStore: RedditDataStore
    @EnvironmentObject var authManager: RedditAuthManager
    @State private var refreshing = false
    
    var body: some View {
        VStack {
            if dataStore.isLoading && !refreshing {
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle())
                    .scaleEffect(1.5)
                    .padding()
            } else if let errorMessage = dataStore.errorMessage {
                Text(errorMessage)
                    .foregroundColor(.red)
                    .padding()
            } else {
                List {
                    ForEach(dataStore.posts) { post in
                        NavigationLink(destination: PostDetailView(post: post, subreddit: subreddit.name)) {
                            PostRowView(post: post)
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                }
                .listStyle(PlainListStyle())
                .refreshable {
                    refreshing = true
                    dataStore.fetchPosts(for: subreddit.name, token: authManager.accessToken)
                    refreshing = false
                }
            }
        }
        .navigationTitle(subreddit.displayName)
        .onAppear {
            dataStore.fetchPosts(for: subreddit.name, token: authManager.accessToken)
        }
    }
}

struct PostRowView: View {
    let post: RedditPost
    @EnvironmentObject var dataStore: RedditDataStore
    @State private var showFullImage = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(post.title)
                .font(.headline)
                .lineLimit(3)
            
            HStack {
                Text("u/\(post.author)")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Text("•")
                    .foregroundColor(.secondary)
                
                Text(post.domain)
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Spacer()
                
                HStack(spacing: 12) {
                    Label("\(post.score)", systemImage: "arrow.up")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Label("\(post.num_comments)", systemImage: "bubble.right")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            if !post.selftext.isEmpty && post.selftext.count <= 100 {
                Text(post.selftext)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
                    .padding(.top, 4)
            }
            
            // Content Preview
            Group {
                switch post.contentType {
                case .selfText:
                    EmptyView()
                case .image:
                    if let imageUrl = getImageUrl(from: post) {
                        KFImage(URL(string: imageUrl))
                            .resizable()
                            .scaledToFill()
                            .frame(height: 150)
                            .clipped()
                            .cornerRadius(8)
                            .onTapGesture {
                                showFullImage = true
                            }
                    }
                case .video:
                    VideoThumbnailView(post: post)
                        .frame(height: 150)
                        .cornerRadius(8)
                case .link:
                    LinkPreviewRow(url: post.url)
                case .gallery:
                    if post.hasGallery {
                        Text("Gallery: \(post.gallery_data?.items.count ?? 0) images")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
        .padding(.vertical, 8)
        .fullScreenCover(isPresented: $showFullImage) {
            if let imageUrl = getImageUrl(from: post), let url = URL(string: imageUrl) {
                FullScreenImageView(imageURL: url)
            }
        }
    }
    
    private func getImageUrl(from post: RedditPost) -> String? {
        if let preview = post.preview, let source = preview.images.first?.source {
            return source.url.replacingOccurrences(of: "&amp;", with: "&")
        }
        return post.url
    }
}

struct VideoThumbnailView: View {
    let post: RedditPost
    
    var body: some View {
        ZStack {
            if let thumbnail = post.thumbnail, thumbnail.hasPrefix("http") {
                KFImage(URL(string: thumbnail))
                    .resizable()
                    .scaledToFill()
                    .frame(maxWidth: .infinity)
                    .clipped()
            } else {
                Rectangle()
                    .fill(Color.black.opacity(0.8))
            }
            
            Image(systemName: "play.circle.fill")
                .resizable()
                .scaledToFit()
                .frame(width: 50, height: 50)
                .foregroundColor(.white)
                .shadow(radius: 2)
            
            VStack {
                Spacer()
                HStack {
                    Text(getVideoSource(post))
                        .font(.caption)
                        .padding(6)
                        .background(Color.black.opacity(0.6))
                        .foregroundColor(.white)
                        .cornerRadius(4)
                    
                    Spacer()
                }
            }
            .padding(8)
        }
    }
    
    private func getVideoSource(_ post: RedditPost) -> String {
        if post.domain.contains("youtube") {
            return "YouTube"
        } else if post.domain.contains("v.redd.it") {
            return "Reddit Video"
        } else {
            return post.domain
        }
    }
}

struct LinkPreviewRow: View {
    let url: String
    @EnvironmentObject var dataStore: RedditDataStore
    
    var metadata: LinkMetadata? {
        return dataStore.linkMetadataCache[url]
    }
    
    var body: some View {
        HStack(spacing: 12) {
            if let metadata = metadata, let imageURL = metadata.imageURL, let imageUrl = URL(string: imageURL) {
                KFImage(imageUrl)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 80, height: 80)
                    .clipped()
                    .cornerRadius(4)
            } else {
                Rectangle()
                    .fill(Color.secondary.opacity(0.2))
                    .frame(width: 80, height: 80)
                    .cornerRadius(4)
                    .overlay(
                        Image(systemName: "link")
                            .foregroundColor(.secondary)
                    )
            }
            
            VStack(alignment: .leading, spacing: 4) {
                if let metadata = metadata {
                    if !metadata.title.isEmpty {
                        Text(metadata.title)
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .lineLimit(2)
                    }
                    
                    if !metadata.description.isEmpty {
                        Text(metadata.description)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(2)
                    }
                    
                    Text(metadata.siteName.isEmpty ? url : metadata.siteName)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                } else {
                    Text(url)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }
            }
        }
        .frame(height: 80)
        .onAppear {
            if dataStore.linkMetadataCache[url] == nil {
                dataStore.fetchLinkMetadata(for: url)
            }
        }
    }
}

struct PostDetailView: View {
    let post: RedditPost
    let subreddit: String
    @EnvironmentObject var dataStore: RedditDataStore
    @EnvironmentObject var authManager: RedditAuthManager
    @State private var showFullImage = false
    @State private var showFullScreen = false
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text(post.title)
                    .font(.title2)
                    .fontWeight(.bold)
                    .padding(.horizontal)
                
                HStack {
                    Text("Posted by u/\(post.author)")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    
                    Spacer()
                    
                    Text(post.createdDate, style: .relative)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal)
                
                Divider()
                
                // Post content
                PostContentView(post: post, showFullScreen: $showFullScreen)
                    .padding(.horizontal)
                
                HStack(spacing: 20) {
                    Label("\(post.score)", systemImage: "arrow.up")
                    Label("\(post.num_comments) comments", systemImage: "bubble.right")
                    Spacer()
                    
                    Button(action: {
                        // Share post
                    }) {
                        Image(systemName: "square.and.arrow.up")
                    }
                }
                .padding()
                .background(Color.secondary.opacity(0.1))
                
                Divider()
                
                if dataStore.isLoading {
                    HStack {
                        Spacer()
                        ProgressView()
                        Spacer()
                    }
                    .padding()
                } else {
                    ForEach(dataStore.comments) { comment in
                        CommentView(comment: comment, level: 0)
                    }
                }
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            dataStore.fetchComments(for: post.id, subreddit: subreddit, token: authManager.accessToken)
        }
        .fullScreenCover(isPresented: $showFullScreen) {
            FullScreenMediaView(post: post)
        }
    }
}

struct PostContentView: View {
    let post: RedditPost
    @Binding var showFullScreen: Bool
    
    var body: some View {
        Group {
            switch post.contentType {
            case .selfText:
                if !post.selftext.isEmpty {
                    Text(post.selftext)
                        .padding(.bottom)
                }
                
            case .image:
                if let imageUrl = getImageUrl(from: post), let url = URL(string: imageUrl) {
                    KFImage(url)
                        .resizable()
                        .scaledToFit()
                        .cornerRadius(8)
                        .onTapGesture {
                            showFullScreen = true
                        }
                }
                
            case .video:
                VideoPlayerView(post: post)
                    .frame(height: 300)
                    .cornerRadius(8)
                    .onTapGesture {
                        showFullScreen = true
                    }
                
            case .link:
                LinkPreviewView(url: post.url)
                    .cornerRadius(8)
                
            case .gallery:
                if post.hasGallery {
                    GalleryView(post: post)
                        .frame(height: 300)
                        .cornerRadius(8)
                }
            }
        }
    }
    
    private func getImageUrl(from post: RedditPost) -> String? {
        if let preview = post.preview, let source = preview.images.first?.source {
            return source.url.replacingOccurrences(of: "&amp;", with: "&")
        }
        return post.url
    }
}

struct VideoPlayerView: View {
    let post: RedditPost
    @State private var isPlaying = false
    
    var videoURL: URL? {
        if let media = post.media, let redditVideo = media.reddit_video {
            return URL(string: redditVideo.fallback_url)
        } else if post.url.contains("youtube.com") || post.url.contains("youtu.be") {
            return URL(string: post.url)
        } else {
            return URL(string: post.url)
        }
    }
    
    var body: some View {
        ZStack {
            if let url = videoURL {
                if post.domain.contains("youtube") {
                    YouTubeView(videoURL: url)
                } else {
                    VideoPlayer(player: AVPlayer(url: url))
                        .onAppear {
                            isPlaying = true
                        }
                        .onDisappear {
                            isPlaying = false
                        }
                }
            } else {
                Rectangle()
                    .fill(Color.black)
                    .overlay(
                        Text("Unable to load video")
                            .foregroundColor(.white)
                    )
            }
        }
    }
}

struct YouTubeView: UIViewRepresentable {
    let videoURL: URL
    
    func makeUIView(context: Context) -> WKWebView {
        let webView = WKWebView()
        webView.scrollView.isScrollEnabled = false
        webView.allowsBackForwardNavigationGestures = false
        return webView
    }
    
    func updateUIView(_ webView: WKWebView, context: Context) {
        // Extract video ID
        var videoID = ""
        let urlString = videoURL.absoluteString
        
        if urlString.contains("youtube.com") {
            if let queryItems = URLComponents(string: urlString)?.queryItems,
               let id = queryItems.first(where: { $0.name == "v" })?.value {
                videoID = id
            }
        } else if urlString.contains("youtu.be") {
            videoID = urlString.components(separatedBy: "/").last ?? ""
        }
        
        if !videoID.isEmpty {
            let embedHTML = """
            <!DOCTYPE html>
            <html>
            <head>
                <meta name="viewport" content="width=device-width, initial-scale=1">
                <style>
                    body { margin: 0; background-color: black; }
                    .video-container { position: relative; padding-bottom: 56.25%; height: 0; overflow: hidden; }
                    .video-container iframe { position: absolute; top: 0; left: 0; width: 100%; height: 100%; }
                </style>
            </head>
            <body>
                <div class="video-container">
                    <iframe width="100%" height="100%" src="https://www.youtube.com/embed/\(videoID)?playsinline=1" frameborder="0" allowfullscreen></iframe>
                </div>
            </body>
            </html>
            """
            
            webView.loadHTMLString(embedHTML, baseURL: nil)
        }
    }
}

struct GalleryView: View {
    let post: RedditPost
    @State private var currentIndex = 0
    
    var galleryItems: [GalleryItem] {
        return post.gallery_data?.items ?? []
    }
    
    var body: some View {
        VStack {
            if galleryItems.isEmpty {
                Text("Gallery couldn't be loaded")
                    .foregroundColor(.secondary)
            } else {
                TabView(selection: $currentIndex) {
                    ForEach(0..<galleryItems.count, id: \.self) { index in
                        if let item = galleryItems[safe: index] {
                            GalleryItemView(mediaID: item.media_id)
                                .tag(index)
                        }
                    }
                }
                .tabViewStyle(PageTabViewStyle())
                
                Text("\(currentIndex + 1) of \(galleryItems.count)")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.top, 8)
            }
        }
    }
}

extension Array {
    subscript(safe index: Index) -> Element? {
        return indices.contains(index) ? self[index] : nil
    }
}

struct GalleryItemView: View {
    let mediaID: String
    
    var imageUrl: String {
        return "https://i.redd.it/\(mediaID).jpg"
    }
    
    var body: some View {
        KFImage(URL(string: imageUrl))
            .resizable()
            .scaledToFit()
            .background(Color.black)
    }
}

struct LinkPreviewView: View {
    let url: String
    @EnvironmentObject var dataStore: RedditDataStore
    @State private var showWebView = false
    
    var metadata: LinkMetadata? {
        return dataStore.linkMetadataCache[url]
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let metadata = metadata {
                if let imageURL = metadata.imageURL, let imageUrl = URL(string: imageURL) {
                    KFImage(imageUrl)
                        .resizable()
                        .scaledToFit()
                        .frame(maxHeight: 200)
                        .clipped()
                }
                
                if !metadata.title.isEmpty {
                    Text(metadata.title)
                        .font(.headline)
                        .lineLimit(2)
                }
                
                if !metadata.description.isEmpty {
                    Text(metadata.description)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .lineLimit(3)
                }
                
                HStack {
                    Text(metadata.siteName.isEmpty ? url : metadata.siteName)
                        .font(.caption)
                        .foregroundColor(.blue)
                    
                    Spacer()
                    
                    Button("Open") {
                        showWebView = true
                    }
                    .font(.caption)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(4)
                }
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, minHeight: 100)
            }
        }
        .padding()
        .background(Color.secondary.opacity(0.1))
        .cornerRadius(8)
        .onTapGesture {
            showWebView = true
        }
        .sheet(isPresented: $showWebView) {
            if let url = URL(string: url) {
                WebViewContainer(url: url)
            }
        }
        .onAppear {
            if dataStore.linkMetadataCache[url] == nil {
                dataStore.fetchLinkMetadata(for: url)
            }
        }
    }
}

struct WebViewContainer: View {
    let url: URL
    @Environment(\.presentationMode) var presentationMode
    
    var body: some View {
        NavigationView {
            WebView(url: url)
                .navigationBarTitle(Text(url.host ?? ""), displayMode: .inline)
                .navigationBarItems(trailing: Button("Done") {
                    presentationMode.wrappedValue.dismiss()
                })
        }
    }
}

struct WebView: UIViewRepresentable {
    let url: URL
    
    func makeUIView(context: Context) -> WKWebView {
        let webView = WKWebView()
        return webView
    }
    
    func updateUIView(_ webView: WKWebView, context: Context) {
        let request = URLRequest(url: url)
        webView.load(request)
    }
}

struct CommentView: View {
    let comment: RedditComment
    let level: Int
    @State private var isCollapsed = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button(action: {
                isCollapsed.toggle()
            }) {
                HStack {
                    Text("u/\(comment.author)")
                        .font(.footnote)
                        .fontWeight(.medium)
                    
                    Spacer()
                    
                    HStack {
                        Text("\(comment.score)")
                            .font(.caption)
                        Image(systemName: "arrow.up")
                            .font(.caption)
                    }
                    
                    Text(comment.createdDate, style: .relative)
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    if isCollapsed {
                        Image(systemName: "chevron.down")
                            .font(.caption)
                    }
                }
            }
            .buttonStyle(PlainButtonStyle())
            
            if !isCollapsed {
                Text(comment.body)
                    .font(.subheadline)
                
                if let replies = comment.replies,
                   let data = replies.data,
                   let children = data.children {
                    ForEach(children.compactMap { $0.data }, id: \.id) { reply in
                        CommentView(comment: reply, level: level + 1)
                            .padding(.leading, 16)
                    }
                }
            }
        }
        .padding()
        .padding(.leading, CGFloat(level * 8))
        .background(
            level % 2 == 0 ? Color.gray.opacity(0.05) : Color.clear
        )
        .overlay(
            Rectangle()
                .fill(getIndentationColor(for: level))
                .frame(width: 2)
                .padding(.vertical, 4),
            alignment: .leading
        )
    }
    
    private func getIndentationColor(for level: Int) -> Color {
        let colors: [Color] = [.blue, .green, .orange, .purple, .pink]
        return colors[level % colors.count].opacity(0.5)
    }
}

struct FullScreenImageView: View {
    let imageURL: URL
    @Environment(\.presentationMode) var presentationMode
    @State private var scale: CGFloat = 1.0
    @State private var lastScale: CGFloat = 1.0
    @State private var offset = CGSize.zero
    @State private var lastOffset = CGSize.zero
    
    var body: some View {
        ZStack {
            Color.black.edgesIgnoringSafeArea(.all)
            
            KFImage(imageURL)
                .resizable()
                .scaledToFit()
                .scaleEffect(scale)
                .offset(offset)
                .gesture(
                    MagnificationGesture()
                        .onChanged { value in
                            let delta = value / lastScale
                            lastScale = value
                            scale *= delta
                        }
                        .onEnded { value in
                            lastScale = 1.0
                        }
                )
                .gesture(
                    DragGesture()
                        .onChanged { value in
                            offset = CGSize(
                                width: lastOffset.width + value.translation.width,
                                height: lastOffset.height + value.translation.height
                            )
                        }
                        .onEnded { value in
                            lastOffset = offset
                        }
                )
                .gesture(
                    TapGesture(count: 2)
                        .onEnded {
                            withAnimation {
                                if scale > 1 {
                                    scale = 1
                                    offset = .zero
                                    lastOffset = .zero
                                } else {
                                    scale = 2
                                }
                            }
                        }
                )
                .onTapGesture {
                    presentationMode.wrappedValue.dismiss()
                }
        }
        .statusBar(hidden: true)
    }
}

struct FullScreenMediaView: View {
    let post: RedditPost
    @Environment(\.presentationMode) var presentationMode
    @State private var currentPage = 0
    
    var body: some View {
        ZStack {
            Color.black.edgesIgnoringSafeArea(.all)
            
            Group {
                switch post.contentType {
                case .image:
                    if let imageUrl = getImageUrl(from: post), let url = URL(string: imageUrl) {
                        FullScreenImageView(imageURL: url)
                    }
                case .video:
                    VideoPlayerFullScreen(post: post)
                case .gallery:
                    GalleryFullScreenView(post: post)
                default:
                    WebViewContainer(url: URL(string: post.url) ?? URL(string: "https://reddit.com")!)
                }
            }
            
            VStack {
                HStack {
                    Button(action: {
                        presentationMode.wrappedValue.dismiss()
                    }) {
                        Image(systemName: "xmark")
                            .font(.system(size: 20))
                            .foregroundColor(.white)
                            .padding(10)
                            .background(Color.black.opacity(0.6))
                            .clipShape(Circle())
                    }
                    .padding()
                    
                    Spacer()
                    
                    Button(action: {
                        // Share
                    }) {
                        Image(systemName: "square.and.arrow.up")
                            .font(.system(size: 20))
                            .foregroundColor(.white)
                            .padding(10)
                            .background(Color.black.opacity(0.6))
                            .clipShape(Circle())
                    }
                    .padding()
                }
                
                Spacer()
            }
        }
        .statusBar(hidden: true)
    }
    
    private func getImageUrl(from post: RedditPost) -> String? {
        if let preview = post.preview, let source = preview.images.first?.source {
            return source.url.replacingOccurrences(of: "&amp;", with: "&")
        }
        return post.url
    }
}

struct VideoPlayerFullScreen: View {
    let post: RedditPost
    
    var videoURL: URL? {
        if let media = post.media, let redditVideo = media.reddit_video {
            return URL(string: redditVideo.fallback_url)
        } else if post.url.contains("youtube.com") || post.url.contains("youtu.be") {
            return URL(string: post.url)
        } else {
            return URL(string: post.url)
        }
    }
    
    var body: some View {
        ZStack {
            Color.black.edgesIgnoringSafeArea(.all)
            
            if let url = videoURL {
                if post.domain.contains("youtube") {
                    YouTubeView(videoURL: url)
                } else {
                    VideoPlayer(player: AVPlayer(url: url))
                        .edgesIgnoringSafeArea(.all)
                }
            } else {
                Text("Unable to load video")
                    .foregroundColor(.white)
            }
        }
    }
}

struct GalleryFullScreenView: View {
    let post: RedditPost
    @State private var currentIndex = 0
    @GestureState private var dragOffset: CGFloat = 0
    
    var galleryItems: [GalleryItem] {
        return post.gallery_data?.items ?? []
    }
    
    var body: some View {
        ZStack {
            Color.black.edgesIgnoringSafeArea(.all)
            
            if galleryItems.isEmpty {
                Text("Gallery couldn't be loaded")
                    .foregroundColor(.white)
            } else {
                GeometryReader { geometry in
                    HStack(spacing: 0) {
                        ForEach(0..<galleryItems.count, id: \.self) { index in
                            if let item = galleryItems[safe: index] {
                                FullScreenGalleryItemView(mediaID: item.media_id)
                                    .frame(width: geometry.size.width, height: geometry.size.height)
                            }
                        }
                    }
                    .offset(x: -CGFloat(currentIndex) * geometry.size.width + dragOffset)
                    .gesture(
                        DragGesture()
                            .updating($dragOffset) { value, state, _ in
                                state = value.translation.width
                            }
                            .onEnded { value in
                                let offset = value.translation.width
                                let threshold = geometry.size.width * 0.35
                                
                                if abs(offset) > threshold {
                                    if offset > 0 && currentIndex > 0 {
                                        withAnimation {
                                            currentIndex -= 1
                                        }
                                    } else if offset < 0 && currentIndex < galleryItems.count - 1 {
                                        withAnimation {
                                            currentIndex += 1
                                        }
                                    }
                                } else {
                                    withAnimation {
                                        // Snap back
                                    }
                                }
                            }
                    )
                }
            }
            
            VStack {
                Spacer()
                
                Text("\(currentIndex + 1) of \(galleryItems.count)")
                    .foregroundColor(.white)
                    .padding(8)
                    .background(Color.black.opacity(0.6))
                    .cornerRadius(8)
                    .padding(.bottom)
            }
        }
    }
}

struct FullScreenGalleryItemView: View {
    let mediaID: String
    @State private var scale: CGFloat = 1.0
    @State private var lastScale: CGFloat = 1.0
    @State private var offset = CGSize.zero
    @State private var lastOffset = CGSize.zero
    
    var imageUrl: String {
        return "https://i.redd.it/\(mediaID).jpg"
    }
    
    var body: some View {
        KFImage(URL(string: imageUrl))
            .resizable()
            .scaledToFit()
            .scaleEffect(scale)
            .offset(offset)
            .gesture(
                MagnificationGesture()
                    .onChanged { value in
                        let delta = value / lastScale
                        lastScale = value
                        scale *= delta
                    }
                    .onEnded { value in
                        lastScale = 1.0
                    }
            )
            .gesture(
                DragGesture()
                    .onChanged { value in
                        offset = CGSize(
                            width: lastOffset.width + value.translation.width,
                            height: lastOffset.height + value.translation.height
                        )
                    }
                    .onEnded { value in
                        lastOffset = offset
                    }
            )
            .gesture(
                TapGesture(count: 2)
                    .onEnded {
                        withAnimation {
                            if scale > 1 {
                                scale = 1
                                offset = .zero
                                lastOffset = .zero
                            } else {
                                scale = 2
                            }
                        }
                    }
            )
    }
}

struct SearchView: View {
    @State private var searchText = ""
    @State private var selectedSegment = 0
    @EnvironmentObject var dataStore: RedditDataStore
    @EnvironmentObject var authManager: RedditAuthManager
    
    var body: some View {
        NavigationView {
            VStack {
                // Search bar
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.secondary)
                    
                    TextField("Search", text: $searchText)
                        .autocapitalization(.none)
                    
                    if !searchText.isEmpty {
                        Button(action: {
                            searchText = ""
                        }) {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .padding(8)
                .background(Color.secondary.opacity(0.1))
                .cornerRadius(10)
                .padding(.horizontal)
                
                // Segment control
                Picker(selection: $selectedSegment, label: Text("Search Type")) {
                    Text("Posts").tag(0)
                    Text("Subreddits").tag(1)
                    Text("Users").tag(2)
                }
                .pickerStyle(SegmentedPickerStyle())
                .padding(.horizontal)
                
                if searchText.isEmpty {
                    VStack {
                        Spacer()
                        Image(systemName: "magnifyingglass")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 60, height: 60)
                            .foregroundColor(.secondary)
                            .padding()
                        
                        Text("Search for content on Reddit")
                            .foregroundColor(.secondary)
                        Spacer()
                    }
                } else {
                    // Search results would go here
                    Text("Search results for '\(searchText)'")
                        .font(.headline)
                        .padding()
                    
                    Spacer()
                }
            }
            .navigationTitle("Search")
        }
    }
}

struct ProfileView: View {
    @EnvironmentObject var authManager: RedditAuthManager
    
    var body: some View {
        NavigationView {
            VStack {
                Image(systemName: "person.circle.fill")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 100, height: 100)
                    .foregroundColor(.blue)
                    .padding()
                
                Text("u/\(authManager.username)")
                    .font(.title)
                    .fontWeight(.bold)
                
                Divider()
                    .padding()
                
                List {
                    NavigationLink(destination: Text("Saved Posts")) {
                        Label("Saved Posts", systemImage: "bookmark")
                    }
                    
                    NavigationLink(destination: Text("Your Comments")) {
                        Label("Your Comments", systemImage: "bubble.left")
                    }
                    
                    NavigationLink(destination: Text("History")) {
                        Label("History", systemImage: "clock")
                    }
                    
                    NavigationLink(destination: Text("Settings")) {
                        Label("Settings", systemImage: "gear")
                    }
                    
                    Section(header: Text("App Settings")) {
                        NavigationLink(destination: Text("Theme")) {
                            Label("Theme", systemImage: "paintbrush")
                        }
                        
                        NavigationLink(destination: Text("Media Preferences")) {
                            Label("Media Preferences", systemImage: "play.rectangle")
                        }
                        
                        NavigationLink(destination: Text("Notifications")) {
                            Label("Notifications", systemImage: "bell")
                        }
                        
                        NavigationLink(destination: Text("About")) {
                            Label("About", systemImage: "info.circle")
                        }
                    }
                }
                
                Button(action: {
                    authManager.signOut()
                }) {
                    Text("Sign Out")
                        .fontWeight(.medium)
                        .foregroundColor(.white)
                        .padding()
                        .frame(maxWidth: .infinity)
                        .background(Color.red)
                        .cornerRadius(10)
                        .padding(.horizontal)
                }
                .padding(.bottom)
            }
            .navigationTitle("Profile")
        }
    }
}

// MARK: - Helper Extensions

// Add necessary dependencies in your project:
// 1. In Package.swift: dependencies: [.package(url: "https://github.com/onevcat/Kingfisher.git", from: "7.0.0")]
// or
// 2. Using CocoaPods: pod 'Kingfisher', '~> 7.0'
