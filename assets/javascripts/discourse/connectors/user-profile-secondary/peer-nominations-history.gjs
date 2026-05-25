import PeerNominationsHistoryPanel from "../../components/peer-nominations-history-panel";

// Outlet context: { siteSettings, currentUser, model }.
// `model` is the user whose profile is being viewed. The panel itself
// handles all data fetching and rendering — this connector exists only
// to gate visibility (admins only, plugin enabled).
const PeerNominationsHistoryConnector = <template>
  <PeerNominationsHistoryPanel @profileUser={{@outletArgs.model}} />
</template>;

PeerNominationsHistoryConnector.shouldRender = function (args, { siteSettings, currentUser }) {
  if (!siteSettings.peer_nominations_enabled) return false;
  if (!currentUser?.admin) return false;
  if (!args?.model?.id) return false;
  return true;
};

export default PeerNominationsHistoryConnector;
