/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/. */

import Shared
import UIKit
import Deferred
import Storage
import WebImage


struct ASPanelUX {
    static let backgroundColor = UIColor(white: 1.0, alpha: 0.5)
}

// Lifecycle
class ActivityStreamPanel: UIViewController, UICollectionViewDelegate {
    weak var homePanelDelegate: HomePanelDelegate? = nil
    let profile: Profile

    lazy private var tableView: UITableView = {
        let tableView = UITableView(frame: CGRect.zero, style: .Grouped)
        tableView.registerClass(SimpleHighlightCell.self, forCellReuseIdentifier: "Cell")
        tableView.registerClass(ASHorizontalScrollCell.self, forCellReuseIdentifier: "TopSite")
        tableView.registerClass(HighlightCell.self, forCellReuseIdentifier: "Highlight")
        tableView.backgroundColor = ASPanelUX.backgroundColor
        tableView.separatorStyle = .None
        tableView.delegate = self
        tableView.dataSource = self
        tableView.rowHeight = UITableViewAutomaticDimension
        tableView.separatorInset = UIEdgeInsetsZero
        tableView.estimatedRowHeight = 65
        tableView.estimatedSectionHeaderHeight = 15
        tableView.sectionHeaderHeight = UITableViewAutomaticDimension
        return tableView
    }()

    var topSiteHandler: ASHorizontalScrollSource!

    //once things get fleshed out we can refactor and find a better home for these
    var topSites: [TopSiteItem] = []
    var history: [Site] = []

    enum Section: Int {
        case topSites
        case history

        static let count = 2

        var title: String? {
            switch self {
                case .history: return "HIGHLIGHTS"
                default: return nil
            }
        }

        var headerHeight: CGFloat {
            switch self {
                case .history: return 40
                default: return 0
            }
        }

        var headerView: UIView? {
            switch self {
                case .history:
                    let view = ASHeaderView()
                    view.title = "HIGHLIGHTS"
                    return view
                default:
                    return nil
            }
        }

        var cellIdentifier: String {
            switch self {
                case .topSites: return "TopSite"
                default: return "Cell"
            }
        }

        init(at indexPath: NSIndexPath) {
            self.init(rawValue: indexPath.section)!
        }

        init(_ section: Int) {
            self.init(rawValue: section)!
        }
    }

    init(profile: Profile) {
        self.profile = profile
        super.init(nibName: nil, bundle: nil)

        NSNotificationCenter.defaultCenter().addObserver(self, selector: #selector(TopSitesPanel.notificationReceived(_:)), name: NotificationFirefoxAccountChanged, object: nil)
        NSNotificationCenter.defaultCenter().addObserver(self, selector: #selector(TopSitesPanel.notificationReceived(_:)), name: NotificationProfileDidFinishSyncing, object: nil)
        NSNotificationCenter.defaultCenter().addObserver(self, selector: #selector(TopSitesPanel.notificationReceived(_:)), name: NotificationPrivateDataClearedHistory, object: nil)
        NSNotificationCenter.defaultCenter().addObserver(self, selector: #selector(TopSitesPanel.notificationReceived(_:)), name: NotificationDynamicFontChanged, object: nil)
    }

    deinit {
        NSNotificationCenter.defaultCenter().removeObserver(self, name: NotificationFirefoxAccountChanged, object: nil)
        NSNotificationCenter.defaultCenter().removeObserver(self, name: NotificationProfileDidFinishSyncing, object: nil)
        NSNotificationCenter.defaultCenter().removeObserver(self, name: NotificationPrivateDataClearedHistory, object: nil)
        NSNotificationCenter.defaultCenter().removeObserver(self, name: NotificationDynamicFontChanged, object: nil)
    }



    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        refreshTopSites(10)
        
        reloadRecentHistoryWithLimit(10)

        view.addSubview(tableView)
        tableView.snp_makeConstraints { (make) in
            make.edges.equalTo(self.view)
        }
    }

    override func traitCollectionDidChange(previousTraitCollection: UITraitCollection?) {
        if let handler = self.topSiteHandler {
            handler.currentTraits = self.traitCollection
        }

    }

}


// Header Views
extension ActivityStreamPanel {

    func tableView(tableView: UITableView, heightForHeaderInSection section: Int) -> CGFloat {
        return Section(section).headerHeight
    }

    func tableView(tableView: UITableView, viewForHeaderInSection section: Int) -> UIView? {
        return Section(section).headerView
    }
}

// Tableview management
extension ActivityStreamPanel: UITableViewDelegate, UITableViewDataSource {

    func numberOfSectionsInTableView(tableView: UITableView) -> Int {
        return Section.count
    }

    func tableView(tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        switch Section(section) {
            case .topSites:
                if topSiteHandler != nil && !topSiteHandler.content.isEmpty {
                    return 1
                } else {
                    return 0
                }
            case .history:
                 return self.history.count
        }
    }

    func tableView(tableView: UITableView, cellForRowAtIndexPath indexPath: NSIndexPath) -> UITableViewCell {
        let identifier = Section(indexPath.section).cellIdentifier
        let cell = tableView.dequeueReusableCellWithIdentifier(identifier, forIndexPath: indexPath)

        switch Section(indexPath.section) {
            case .topSites:
                return configureTopSitesCell(cell, forIndexPath: indexPath)
            default:
                return configureHistoryItemCell(cell, forIndexPath: indexPath)
        }
    }

    func configureTopSitesCell(cell: UITableViewCell, forIndexPath indexPath: NSIndexPath) -> UITableViewCell {
        let topSiteCell = cell as! ASHorizontalScrollCell
        // The topSiteCell needs a refrence to the tableview because it needs to alert the tableView to relayout once topsites finishes loading.
        topSiteCell.parentTableView = self.tableView
        topSiteCell.setDelegate(self.topSiteHandler)
        return cell
    }

    func configureHistoryItemCell(cell: UITableViewCell, forIndexPath indexPath: NSIndexPath) -> UITableViewCell {
        let simpleHighlightCell = cell as! SimpleHighlightCell
        let site = history[indexPath.row]
        simpleHighlightCell.configureSimpleHighlightCell(site)
        return simpleHighlightCell
    }

    func showSiteWithURL(url: NSURL) {
        let visitType = VisitType.Bookmark
        homePanelDelegate?.homePanel(self, didSelectURL: url, visitType: visitType)
    }

    func tableView(tableView: UITableView, didSelectRowAtIndexPath indexPath: NSIndexPath) {
        switch Section(indexPath.section) {
        case .history:
            let site = self.history[indexPath.row]
            showSiteWithURL(NSURL(string:site.url)!)
        default:
            return
        }
    }
}

// Data Management
extension ActivityStreamPanel {
    /*
     Simple methods to fetch some data from the DB
     */

    func notificationReceived(notification: NSNotification) {
        switch notification.name {
        case NotificationProfileDidFinishSyncing:
            // Only reload top sites if there the cache is dirty since the finish syncing
            // notification is fired everytime the user re-enters the app from the background.
            self.profile.history.areTopSitesDirty(withLimit: 10) >>== { dirty in
                if dirty {
                    self.refreshTopSites(10)
                }
            }
        case NotificationFirefoxAccountChanged, NotificationPrivateDataClearedHistory, NotificationDynamicFontChanged:
            self.refreshTopSites(10)
        default:
            // no need to do anything at all
            print("Dont have this notification type")
        }
    }

    private func refreshTopSites(frecencyLimit: Int) {
        dispatch_async(dispatch_get_main_queue()) {
            // Reload right away with whatever is in the cache, then check to see if the cache is invalid.
            // If it's invalid, invalidate the cache and requery. This allows us to always show results
            // immediately while also loading up-to-date results asynchronously if needed.
            self.reloadTopSitesWithLimit(frecencyLimit) >>> {
                self.profile.history.updateTopSitesCacheIfInvalidated() >>== { dirty in
                    if dirty {
                        self.reloadTopSitesWithLimit(frecencyLimit)
                    }
                }
            }
        }
    }

    private func reloadTopSitesWithLimit(limit: Int) -> Success {
        return self.profile.history.getTopSitesWithLimit(limit).bindQueue(dispatch_get_main_queue()) { result in
            if let data = result.successValue {
                self.topSites = data.asArray().map { site in
                    if let favURL = site.icon?.url {
                        return TopSiteItem(urlTitle: site.tileURL.extractDomainName(), faviconURL: NSURL(string: favURL)!, siteURL: site.tileURL)
                    }
                    return TopSiteItem(urlTitle: site.tileURL.extractDomainName(), faviconURL: nil, siteURL: site.tileURL)
                }
                self.topSiteHandler = ASHorizontalScrollSource()
                self.topSiteHandler.content = self.topSites
                self.topSiteHandler.urlPressedHandler = self.showSiteWithURL
                self.topSiteHandler.currentTraits = self.traitCollection
                self.tableView.reloadData()
            }
            return succeed()
        }
    }

    private func reloadRecentHistoryWithLimit(limit: Int) -> Success {
        return self.profile.history.getSitesByLastVisit(limit).bindQueue(dispatch_get_main_queue()) { result in
            if let data = result.successValue {
                self.history = data.asArray()
                self.tableView.reloadData()
            }
            return succeed()
        }
    }
}

// HomePanel Protocol
extension ActivityStreamPanel: HomePanel {

    func endEditing() {

    }

}