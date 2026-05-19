import { withPluginApi } from "discourse/lib/plugin-api";
import { i18n } from "discourse-i18n";
import PeerNominateModal from "../components/peer-nominate-modal";

export default {
  name: "peer-nominate-topic-footer",

  initialize(container) {
    const siteSettings = container.lookup("service:site-settings");
    if (!siteSettings.peer_nominations_enabled) return;

    withPluginApi("1.0", (api) => {
      api.registerTopicFooterButton({
        id: "peer-nominate-topic-author",
        icon: "certificate",
        priority: 220,
        displayed() {
          if (!this.currentUser) return false;
          const created_by = this.topic?.details?.created_by;
          return !!created_by;
        },
        label() {
          const created_by = this.topic?.details?.created_by;
          if (this.currentUser?.id === created_by?.id) {
            return "peer_nominations.topic_footer.label_self";
          }
          return "peer_nominations.topic_footer.label";
        },
        title() {
          const created_by = this.topic?.details?.created_by;
          if (this.currentUser?.id === created_by?.id) {
            return "peer_nominations.topic_footer.title_self";
          }
          return "peer_nominations.topic_footer.title";
        },
        action() {
          const created_by = this.topic?.details?.created_by;
          if (!created_by) return;
          const modal = container.lookup("service:modal");
          modal.show(PeerNominateModal, {
            model: {
              profileUser: created_by,
              isSelf: this.currentUser?.id === created_by.id,
            },
          });
        },
      });
    });
  },
};
